package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	textencoding "golang.org/x/text/encoding"
	"golang.org/x/text/encoding/korean"
	"golang.org/x/text/transform"
)

var errCtrlCHangup = errors.New("ctrl-c hangup requested")
var errATHHangup = errors.New("ath hangup requested")

// bridge listens on a local TCP port and, for each incoming connection,
// spawns an SSH command and pipes the TCP stream bidirectionally through it.
//
// Environment variables:
//   BRIDGE_PORT  - TCP port to listen on (default: 2323)
//   BRIDGE_CMD_TEMPLATE - command template for outbound SSH sessions.
//                         Placeholders: {host} {port} {userhost}
//                         (default: "ssh -t -t -o StrictHostKeyChecking=accept-new -p {port} {userhost}")
//   BRIDGE_SSH_USER     - SSH username for {userhost} (default: "bbs")
//                         Can also be set as user@host to override dialed host.
//   BRIDGE_DEBUG        - set to 1/true/yes/on to log CONNECT-state stream bytes
//                         (client->ssh and ssh->client) (default: off)
//                         Server-side logs include raw bytes before repair/conversion.
//                         Logs also include an encoding guess.
//   BRIDGE_CLIENT_ENCODING - optional input conversion before SSH:
//                         off|utf8 (default): no conversion
//                         euc-kr|cp949|wansung: decode to UTF-8
//   BRIDGE_SERVER_ENCODING - optional output conversion before DOS client:
//                         off|utf8 (default): no conversion
//                         euc-kr|cp949|wansung: encode UTF-8 to legacy Korean
//   BRIDGE_SERVER_REPAIR_MOJIBAKE - repair common UTF-8 mojibake in server echo
//                                   before legacy encoding (default: true)
//   BRIDGE_ANSI_RESET_HACK - replace ANSI reset sequence ESC[0m with
//                            ESC[0;1;37;40m on server output stream.
//                            Useful for old DOS clients that don't handle modern
//                            reset semantics well. (default: true)
//   BRIDGE_CONNECT_TIMEOUT_SEC - TCP probe timeout before dialing (default: 5)
//   BRIDGE_BUSY_REPEAT - busy.wav repeat count on timeout/unreachable (default: 5)
//   BRIDGE_BUSY_GAP_MS - silent gap between repeated busy tones (default: 0)
//   BRIDGE_CTRL_C_HANGUP - if true, Ctrl+C disconnects active session
//                          (default: true)
//   BRIDGE_DTMF_GAP_MS - silent gap between DTMF digits during dial playback
//                        (default: 320)
//   BRIDGE_POST_DTMF_DELAY_MS - pause after DTMF sequence before connection
//                               result signaling (default: 500)
//
// On Linux/macOS BRIDGE_CMD_TEMPLATE can use the system ssh binary.
// On Windows, set BRIDGE_CMD_TEMPLATE to use the bundled plink.exe, e.g.:
//   BRIDGE_CMD_TEMPLATE=C:\path\to\plink.exe -t -P {port} {userhost}

func main() {
	port := getenv("BRIDGE_PORT", "2323")
	legacyCmd := strings.TrimSpace(getenv("BRIDGE_CMD", ""))
	cmdTemplate := getenv(
		"BRIDGE_CMD_TEMPLATE",
		"ssh -t -t -o StrictHostKeyChecking=accept-new -p {port} {userhost}",
	)
	sshUser := getenv("BRIDGE_SSH_USER", "bbs")
	debugEnabled := parseBoolEnv(getenv("BRIDGE_DEBUG", "0"))
	clientEncoding := strings.ToLower(strings.TrimSpace(getenv("BRIDGE_CLIENT_ENCODING", "off")))
	serverEncoding := strings.ToLower(strings.TrimSpace(getenv("BRIDGE_SERVER_ENCODING", "off")))
	serverRepairMojibake := parseBoolEnv(getenv("BRIDGE_SERVER_REPAIR_MOJIBAKE", "1"))
	ansiResetHack := parseBoolEnv(getenv("BRIDGE_ANSI_RESET_HACK", "1"))
	connectTimeoutSec, _ := strconv.Atoi(getenv("BRIDGE_CONNECT_TIMEOUT_SEC", "5"))
	if connectTimeoutSec <= 0 {
		connectTimeoutSec = 5
	}
	connectTimeout := time.Duration(connectTimeoutSec) * time.Second
	busyRepeat, _ := strconv.Atoi(getenv("BRIDGE_BUSY_REPEAT", "5"))
	if busyRepeat <= 0 {
		busyRepeat = 5
	}
	busyGapMs, _ := strconv.Atoi(getenv("BRIDGE_BUSY_GAP_MS", "0"))
	if busyGapMs < 0 {
		busyGapMs = 0
	}
	if busyGapMs > 5000 {
		busyGapMs = 5000
	}
	ctrlCHangup := parseBoolEnv(getenv("BRIDGE_CTRL_C_HANGUP", "1"))
	dtmfGapMs, _ := strconv.Atoi(getenv("BRIDGE_DTMF_GAP_MS", "320"))
	if dtmfGapMs < 0 {
		dtmfGapMs = 0
	}
	if dtmfGapMs > 1000 {
		dtmfGapMs = 1000
	}
	postDtmfDelayMs, _ := strconv.Atoi(getenv("BRIDGE_POST_DTMF_DELAY_MS", "500"))
	if postDtmfDelayMs < 0 {
		postDtmfDelayMs = 0
	}
	if postDtmfDelayMs > 10000 {
		postDtmfDelayMs = 10000
	}

	addr := "127.0.0.1:" + port
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("bridge: cannot listen on %s: %v", addr, err)
	}
	log.Printf("bridge: listening on %s", addr)
	if legacyCmd != "" {
		log.Printf("bridge: mode=legacy (BRIDGE_CMD)")
		log.Printf("bridge: legacy command: %s", legacyCmd)
	} else {
		log.Printf("bridge: mode=atdt-parser")
		log.Printf("bridge: command template: %s", cmdTemplate)
	}
	if sshUser != "" {
		log.Printf("bridge: ssh user: %s", sshUser)
	}
	if debugEnabled {
		log.Printf("bridge: debug stream logging enabled (BRIDGE_DEBUG)")
	}
	if clientEncoding != "" && clientEncoding != "off" && clientEncoding != "utf8" {
		log.Printf("bridge: client encoding conversion enabled: %s -> utf8", clientEncoding)
	}
	if serverEncoding != "" && serverEncoding != "off" && serverEncoding != "utf8" {
		log.Printf("bridge: server encoding conversion enabled: utf8 -> %s", serverEncoding)
	}
	if ansiResetHack {
		log.Printf("bridge: ansi reset rewrite enabled (ESC[0m -> ESC[0;1;37;40m)")
	}

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("bridge: accept error: %v", err)
			continue
		}
		log.Printf("bridge: accepted connection from %s", conn.RemoteAddr())
		go handle(conn, legacyCmd, cmdTemplate, sshUser, debugEnabled, clientEncoding, serverEncoding, serverRepairMojibake, ansiResetHack, connectTimeout, busyRepeat, busyGapMs, ctrlCHangup, dtmfGapMs, postDtmfDelayMs)
	}
}

func handle(conn net.Conn, legacyCmd, cmdTemplate, sshUser string, debugEnabled bool, clientEncoding, serverEncoding string, serverRepairMojibake bool, ansiResetHack bool, connectTimeout time.Duration, busyRepeat int, busyGapMs int, ctrlCHangup bool, dtmfGapMs int, postDtmfDelayMs int) {
	defer conn.Close()
	sessionID := conn.RemoteAddr().String()
	if legacyCmd != "" {
		parts := strings.Fields(legacyCmd)
		if len(parts) == 0 {
			log.Printf("bridge[%s]: BRIDGE_CMD is empty", sessionID)
			return
		}
		log.Printf("bridge[%s]: legacy connect via %s %s", sessionID, parts[0], strings.Join(parts[1:], " "))
		if err := runConnectedSession(conn, conn, sessionID, parts[0], parts[1:], false, debugEnabled, clientEncoding, serverEncoding, serverRepairMojibake, ansiResetHack, nil, ctrlCHangup); err != nil {
			log.Printf("bridge[%s]: legacy session failed: %v", sessionID, err)
		}
		return
	}

	reader := bufio.NewReader(conn)
	echoEnabled := true

	for {
		line, err := readATCommand(reader, conn, echoEnabled, sessionID)
		if err != nil {
			if err != io.EOF {
				log.Printf("bridge[%s]: read command error: %v", sessionID, err)
			}
			log.Printf("bridge[%s]: disconnected before CONNECT", sessionID)
			return
		}
		cmd := strings.TrimSpace(line)
		if cmd == "" {
			continue
		}
		upper := normalizeHayesCommand(cmd)
		if upper == "" {
			continue
		}
		log.Printf("bridge[%s]: modem cmd: %q", sessionID, cmd)

		switch {
		case upper == "+++":
			writeModemResponse(conn, "OK")

		case !strings.HasPrefix(upper, "AT"):
			// Hayes-style command mode: input must start with AT.
			writeModemResponse(conn, "ERROR")

		case strings.HasPrefix(upper, "ATDT"), strings.HasPrefix(upper, "ATD"):
			rawTarget := ""
			if strings.HasPrefix(upper, "ATDT") {
				rawTarget = strings.TrimSpace(cmd[4:])
			} else {
				rawTarget = strings.TrimSpace(cmd[3:])
			}

			// Hayes-like empty dial behavior:
			// - ATDT / ATD      -> off-hook dial tone wait, then NO CARRIER
			// - ATDT; / ATD;    -> return to command mode with OK
			if rawTarget == ";" {
				log.Printf("bridge[%s]: empty dial with ';' modifier -> OK", sessionID)
				if err := playEmbeddedSound("tone.wav"); err != nil {
					log.Printf("bridge[%s]: tone playback failed for ATD;: %v", sessionID, err)
				}
				writeModemResponse(conn, "OK")
				continue
			}
			if rawTarget == "" {
				log.Printf("bridge[%s]: empty dial -> tone.wav once then NO CARRIER", sessionID)
				if err := playEmbeddedSound("tone.wav"); err != nil {
					log.Printf("bridge[%s]: tone playback failed for empty ATD: %v", sessionID, err)
				}
				writeModemResponse(conn, "NO CARRIER")
				continue
			}

			host, port, parseErr := parseDialTarget(rawTarget)
			if parseErr != nil {
				log.Printf("bridge[%s]: invalid ATDT target %q: %v", sessionID, rawTarget, parseErr)
				writeModemResponse(conn, "ERROR")
				continue
			}

			execPath, execArgs, buildErr := buildOutboundCommand(cmdTemplate, sshUser, host, port)
			if buildErr != nil {
				log.Printf("bridge[%s]: command template error: %v", sessionID, buildErr)
				writeModemResponse(conn, "ERROR")
				continue
			}
			logOutboundDialDebug(sessionID, sshUser, host, port, execPath, execArgs)
			log.Printf("bridge[%s]: dialing SSH target %s:%s via %s %s", sessionID, host, port, execPath, strings.Join(execArgs, " "))

			if err := dialWhileProbing(rawTarget, host, port, connectTimeout, sessionID, dtmfGapMs, postDtmfDelayMs); err != nil {
				log.Printf("bridge[%s]: outbound probe failed for %s:%s: %v", sessionID, host, port, err)
				playBusyTones(sessionID, busyRepeat, busyGapMs)
				writeModemResponse(conn, "NO CARRIER")
				continue
			}

			// Target is reachable: play ring + modem tones before CONNECT.
			if err := playRingingAndModem(sessionID); err != nil {
				log.Printf("bridge[%s]: ringing/modem playback failed: %v", sessionID, err)
				writeModemResponse(conn, "NO CARRIER")
				continue
			}

			if err := runConnectedSession(conn, reader, sessionID, execPath, execArgs, true, debugEnabled, clientEncoding, serverEncoding, serverRepairMojibake, ansiResetHack, nil, ctrlCHangup); err != nil {
				if errors.Is(err, errCtrlCHangup) {
					log.Printf("bridge[%s]: user hangup via Ctrl+C", sessionID)
					writeModemResponse(conn, "NO CARRIER")
					continue
				}
				if errors.Is(err, errATHHangup) {
					// Hayes-style local hangup command acknowledgment.
					log.Printf("bridge[%s]: user hangup via ATH", sessionID)
					writeModemResponse(conn, "OK")
					continue
				}
				log.Printf("bridge[%s]: connect failed: %v", sessionID, err)
				playBusyTones(sessionID, busyRepeat, busyGapMs)
				writeModemResponse(conn, "NO CARRIER")
				continue
			}
			// Remote session ended normally (e.g. BBS disconnect). Emulate modem
			// carrier drop and return to command mode so the user can redial.
			writeModemResponse(conn, "NO CARRIER")
			continue

		case strings.HasPrefix(upper, "ATE0"):
			echoEnabled = false
			writeModemResponse(conn, "OK")

		case strings.HasPrefix(upper, "ATE1"):
			echoEnabled = true
			writeModemResponse(conn, "OK")

		case strings.HasPrefix(upper, "AT"):
			switch {
			case upper == "AT" || upper == "ATZ" || upper == "AT&F":
				writeModemResponse(conn, "OK")
			case strings.HasPrefix(upper, "ATH"):
				// Valid hangup forms are ATH / ATH0 / ATH1.
				if upper == "ATH" || upper == "ATH0" || upper == "ATH1" {
					writeModemResponse(conn, "OK")
				} else {
					writeModemResponse(conn, "ERROR")
				}
			case strings.HasPrefix(upper, "ATI"):
				// Minimal modem identification response.
				writeModemResponse(conn, "IYAGI BRIDGE MODEM")
				writeModemResponse(conn, "OK")
			case isLikelyHayesInitCommand(upper):
				// Accept common init strings such as:
				// AT&C1\N3L3S11=60%A127%c1\c1
				writeModemResponse(conn, "OK")
			default:
				writeModemResponse(conn, "ERROR")
			}

		default:
			writeModemResponse(conn, "ERROR")
		}
	}
}

func runConnectedSession(conn net.Conn, input io.Reader, sessionID, execPath string, execArgs []string, sendConnect bool, debugEnabled bool, clientEncoding, serverEncoding string, serverRepairMojibake bool, ansiResetHack bool, preConnect func() error, ctrlCHangup bool) error {
	// This function may set a read deadline to unblock the client read loop when
	// the remote session exits. Clear it before returning so command mode can
	// continue accepting AT commands after NO CARRIER.
	defer func() {
		_ = conn.SetReadDeadline(time.Time{})
	}()

	c := exec.Command(execPath, execArgs...)

	stdin, err := c.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}
	stdout, err := c.StdoutPipe()
	if err != nil {
		return fmt.Errorf("stdout pipe: %w", err)
	}
	c.Stderr = os.Stderr

	if err := c.Start(); err != nil {
		return fmt.Errorf("start %q: %w", execPath, err)
	}
	log.Printf("bridge[%s]: spawned %s (pid %d)", sessionID, execPath, c.Process.Pid)
	waitCh := make(chan error, 1)
	go func() {
		waitCh <- c.Wait()
	}()
	waitResultCh := make(chan error, 1)
	go func() {
		err := <-waitCh
		// If remote side exits first, unblock any client-side read so the session
		// can return promptly and emit NO CARRIER without waiting for Enter.
		_ = conn.SetReadDeadline(time.Now())
		waitResultCh <- err
	}()
	if preConnect != nil {
		if err := preConnect(); err != nil {
			_ = c.Process.Kill()
			<-waitResultCh
			return fmt.Errorf("pre-connect action failed: %w", err)
		}
	}
	select {
	case err := <-waitResultCh:
		if err != nil {
			return fmt.Errorf("session ended before CONNECT: %w", err)
		}
		return fmt.Errorf("session ended before CONNECT")
	default:
	}
	if sendConnect {
		writeModemResponse(conn, "CONNECT")
	}

	var wg sync.WaitGroup
	wg.Add(2)
	clientCopyErrCh := make(chan error, 1)

	go func() {
		defer wg.Done()
		defer stdin.Close()

		inputReader := applyClientEncodingReader(input, clientEncoding)
		clientCopyErrCh <- copyClientStreamWithDisconnect(stdin, inputReader, conn, sessionID, debugEnabled, ctrlCHangup)
	}()

	go func() {
		defer wg.Done()
		serverSource := io.Reader(stdout)
		if debugEnabled {
			// Log server bytes exactly as received from SSH before any repair/conversion.
			serverSource = io.TeeReader(serverSource, newDebugTapWriter(sessionID, "ssh->bridge(raw-src)"))
		}
		serverReader := maybeRepairServerMojibakeReader(serverSource, serverRepairMojibake)
		serverReader = maybeRewriteANSIResetReader(serverReader, ansiResetHack)
		outputReader := applyServerEncodingReader(serverReader, serverEncoding)
		if debugEnabled {
			outputReader = io.TeeReader(outputReader, newDebugTapWriter(sessionID, "bridge->client(conv)"))
		}
		io.Copy(conn, outputReader) //nolint:errcheck
	}()

	wg.Wait()
	log.Printf("bridge[%s]: TCP piping finished", sessionID)
	clientCopyErr := <-clientCopyErrCh
	if errors.Is(clientCopyErr, errCtrlCHangup) {
		log.Printf("bridge[%s]: terminating SSH process due to Ctrl+C", sessionID)
		if c.Process != nil {
			_ = c.Process.Kill()
		}
		<-waitResultCh
		return errCtrlCHangup
	}
	if nerr, ok := clientCopyErr.(net.Error); ok && nerr.Timeout() {
		// Expected when remote side exits and SetReadDeadline is used to unblock input.
		clientCopyErr = nil
	}
	if clientCopyErr != nil && !errors.Is(clientCopyErr, io.EOF) {
		log.Printf("bridge[%s]: client stream ended with error: %v", sessionID, clientCopyErr)
	}
	if err := <-waitResultCh; err != nil {
		return fmt.Errorf("session ended: %w", err)
	}
	log.Printf("bridge[%s]: session ended cleanly", sessionID)
	return nil
}

func copyClientStreamWithDisconnect(dst io.Writer, src io.Reader, modemConn net.Conn, sessionID string, debugEnabled, ctrlCHangup bool) error {
	const escapeGuard = 1 * time.Second

	buf := make([]byte, 1024)
	var lastByteAt time.Time
	pendingPluses := make([]byte, 0, 3)
	inCommandMode := false
	cmdBuf := make([]byte, 0, 128)

	flushPendingPluses := func() error {
		if len(pendingPluses) == 0 {
			return nil
		}
		if _, err := dst.Write(pendingPluses); err != nil {
			return err
		}
		pendingPluses = pendingPluses[:0]
		return nil
	}

	processCommandByte := func(b byte) error {
		switch b {
		case 0x08, 0x7f:
			if len(cmdBuf) > 0 {
				cmdBuf = cmdBuf[:len(cmdBuf)-1]
				_, _ = io.WriteString(modemConn, "\b \b")
			}
		case '\r', '\n':
			if len(cmdBuf) == 0 {
				return nil
			}
			_, _ = io.WriteString(modemConn, "\r\n")
			cmd := strings.TrimSpace(string(cmdBuf))
			upper := normalizeHayesCommand(cmd)
			upper = strings.TrimLeft(upper, "+")
			cmdBuf = cmdBuf[:0]
			if upper == "" {
				return nil
			}
			log.Printf("bridge[%s]: online-cmd: %q", sessionID, upper)
			switch {
			case strings.HasPrefix(upper, "ATH"):
				return errATHHangup
			case strings.HasPrefix(upper, "ATO"):
				inCommandMode = false
				writeModemResponse(modemConn, "CONNECT")
				return nil
			case strings.HasPrefix(upper, "AT"):
				writeModemResponse(modemConn, "OK")
				return nil
			default:
				writeModemResponse(modemConn, "ERROR")
				return nil
			}
		default:
			cmdBuf = append(cmdBuf, b)
			if b >= 32 && b <= 126 {
				_, _ = modemConn.Write([]byte{b})
			}
		}
		return nil
	}

	for {
		n, err := src.Read(buf)
		now := time.Now()
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			// Always log everything received from COM/client side so modem-control
			// behavior (disconnect/hangup retries, escape timing, etc.) is visible.
			log.Printf(
				"bridge[%s]: com-rx(online): %s | %s",
				sessionID,
				debugBytes(chunk),
				detectEncodingSummary(chunk),
			)
			if debugEnabled {
				log.Printf(
					"bridge[%s][debug] client->ssh: %s | %s",
					sessionID,
					debugBytes(chunk),
					detectEncodingSummary(chunk),
				)
			}

			for _, b := range chunk {
				if inCommandMode {
					if cmdErr := processCommandByte(b); cmdErr != nil {
						return cmdErr
					}
					lastByteAt = now
					continue
				}

				if len(pendingPluses) == 3 && now.Sub(lastByteAt) >= escapeGuard {
					// Guard-time after "+++" passed: enter online command mode.
					pendingPluses = pendingPluses[:0]
					inCommandMode = true
					if cmdErr := processCommandByte(b); cmdErr != nil {
						return cmdErr
					}
					lastByteAt = now
					continue
				}

				if b == '+' {
					if len(pendingPluses) == 0 {
						// Guard-time before escape sequence.
						if !lastByteAt.IsZero() && now.Sub(lastByteAt) < escapeGuard {
							if _, werr := dst.Write([]byte{b}); werr != nil {
								return werr
							}
							lastByteAt = now
							continue
						}
						pendingPluses = append(pendingPluses, b)
						lastByteAt = now
						continue
					}
					if len(pendingPluses) < 3 && now.Sub(lastByteAt) < escapeGuard {
						pendingPluses = append(pendingPluses, b)
						lastByteAt = now
						continue
					}
				}

				if len(pendingPluses) > 0 {
					if err := flushPendingPluses(); err != nil {
						return err
					}
				}

				if b == 0x03 && ctrlCHangup {
					return errCtrlCHangup
				}
				if _, werr := dst.Write([]byte{b}); werr != nil {
					return werr
				}
				lastByteAt = now
			}
		}
		if err != nil {
			if len(pendingPluses) > 0 {
				if ferr := flushPendingPluses(); ferr != nil {
					return ferr
				}
			}
			if debugEnabled && err != io.EOF {
				log.Printf("bridge[%s][debug] read from client failed: %v", sessionID, err)
			}
			return err
		}
	}
}

func debugBytes(p []byte) string {
	const max = 256
	var b strings.Builder
	limit := len(p)
	if limit > max {
		limit = max
	}
	for i := 0; i < limit; i++ {
		c := p[i]
		switch c {
		case '\r':
			b.WriteString(`\r`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		case '\b':
			b.WriteString(`\b`)
		default:
			if c >= 32 && c <= 126 {
				b.WriteByte(c)
			} else {
				fmt.Fprintf(&b, `\x%02x`, c)
			}
		}
	}
	if len(p) > max {
		fmt.Fprintf(&b, "...(+%d bytes)", len(p)-max)
	}
	return b.String()
}

type debugTapWriter struct {
	sessionID string
	label     string
}

func newDebugTapWriter(sessionID, label string) *debugTapWriter {
	return &debugTapWriter{sessionID: sessionID, label: label}
}

func (w *debugTapWriter) Write(p []byte) (int, error) {
	if len(p) > 0 {
		log.Printf(
			"bridge[%s][debug] %s: %s | %s",
			w.sessionID,
			w.label,
			debugBytes(p),
			detectEncodingSummary(p),
		)
	}
	return len(p), nil
}

func detectEncodingSummary(p []byte) string {
	if len(p) == 0 {
		return "enc=empty"
	}

	asciiPrintable := 0
	asciiControl := 0
	highBytes := 0
	for _, c := range p {
		switch {
		case c >= 32 && c <= 126:
			asciiPrintable++
		case c == '\r' || c == '\n' || c == '\t' || c == '\b':
			asciiControl++
		case c >= 128:
			highBytes++
		}
	}

	if highBytes == 0 {
		return fmt.Sprintf(
			"enc_guess=ascii printable=%d control=%d len=%d",
			asciiPrintable,
			asciiControl,
			len(p),
		)
	}

	if utf8.Valid(p) {
		return fmt.Sprintf("enc_guess=utf8 high=%d len=%d", highBytes, len(p))
	}

	eucPairs, eucInvalid := countEUCKRPairs(p)
	cp949Pairs, cp949Invalid := countCP949Pairs(p)

	switch {
	case cp949Pairs > 0 && cp949Invalid == 0:
		return fmt.Sprintf("enc_guess=cp949-like pairs=%d len=%d", cp949Pairs, len(p))
	case eucPairs > 0 && eucInvalid == 0:
		return fmt.Sprintf("enc_guess=euc-kr-like pairs=%d len=%d", eucPairs, len(p))
	case cp949Pairs > eucPairs:
		return fmt.Sprintf(
			"enc_guess=likely-cp949-ish pairs=%d invalid=%d len=%d",
			cp949Pairs,
			cp949Invalid,
			len(p),
		)
	case eucPairs > 0:
		return fmt.Sprintf(
			"enc_guess=likely-euc-kr-ish pairs=%d invalid=%d len=%d",
			eucPairs,
			eucInvalid,
			len(p),
		)
	default:
		return fmt.Sprintf("enc_guess=unknown high=%d len=%d", highBytes, len(p))
	}
}

func countEUCKRPairs(p []byte) (pairs int, invalid int) {
	for i := 0; i < len(p); i++ {
		c := p[i]
		if c < 0x80 {
			continue
		}
		if i+1 >= len(p) {
			invalid++
			break
		}
		n := p[i+1]
		if c >= 0xA1 && c <= 0xFE && n >= 0xA1 && n <= 0xFE {
			pairs++
			i++
			continue
		}
		invalid++
	}
	return pairs, invalid
}

func countCP949Pairs(p []byte) (pairs int, invalid int) {
	for i := 0; i < len(p); i++ {
		c := p[i]
		if c < 0x80 {
			continue
		}
		if i+1 >= len(p) {
			invalid++
			break
		}
		n := p[i+1]
		leadOK := c >= 0x81 && c <= 0xFE
		trailOK := (n >= 0x41 && n <= 0x5A) || (n >= 0x61 && n <= 0x7A) || (n >= 0x81 && n <= 0xFE)
		if leadOK && trailOK {
			pairs++
			i++
			continue
		}
		invalid++
	}
	return pairs, invalid
}

func readATCommand(r *bufio.Reader, conn net.Conn, echoEnabled bool, sessionID string) (string, error) {
	buf := make([]byte, 0, 128)
	for {
		ch, err := r.ReadByte()
		if err != nil {
			if err == io.EOF && len(buf) > 0 {
				return string(buf), nil
			}
			return "", err
		}
		// Always log bytes received from COM/client while in command mode.
		// Commented out per request to reduce per-keystroke noise:
		// sample := []byte{ch}
		// log.Printf(
		// 	"bridge[%s]: com-rx(cmd): %s | %s",
		// 	sessionID,
		// 	debugBytes(sample),
		// 	detectEncodingSummary(sample),
		// )
		// Handle terminal-style line editing in command mode.
		if ch == 0x08 || ch == 0x7f {
			if len(buf) > 0 {
				buf = buf[:len(buf)-1]
				if echoEnabled {
					_, _ = io.WriteString(conn, "\b \b")
				}
			}
			continue
		}
		if ch == '\r' || ch == '\n' {
			if len(buf) == 0 {
				continue
			}
			if echoEnabled {
				_, _ = io.WriteString(conn, "\r\n")
			}
			return string(buf), nil
		}
		if echoEnabled && ch >= 32 && ch <= 126 {
			_, _ = conn.Write([]byte{ch})
		}
		buf = append(buf, ch)
	}
}

func normalizeHayesCommand(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r < 32 || r > 126 {
			continue
		}
		b.WriteRune(r)
	}
	return strings.ToUpper(strings.TrimSpace(b.String()))
}

func isLikelyHayesInitCommand(cmd string) bool {
	if !strings.HasPrefix(cmd, "AT") || len(cmd) <= 2 {
		return false
	}
	if strings.Contains(cmd, " ") {
		return false
	}
	// Be tolerant for legacy init sequences but reject obvious invalid forms.
	allowed := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&\\%=:;,+-./?"
	for i := 2; i < len(cmd); i++ {
		if !strings.ContainsRune(allowed, rune(cmd[i])) {
			return false
		}
	}
	return true
}

func parseDialTarget(target string) (host, port string, err error) {
	t := strings.TrimSpace(target)
	if t == "" {
		return "", "", fmt.Errorf("empty target")
	}
	if strings.Contains(t, "://") {
		return "", "", fmt.Errorf("unexpected scheme in %q", t)
	}
	parts := strings.Split(t, ":")
	if len(parts) == 1 {
		return parts[0], "22", nil
	}
	if len(parts) != 2 {
		return "", "", fmt.Errorf("unsupported host:port format %q", t)
	}
	host = strings.TrimSpace(parts[0])
	port = strings.TrimSpace(parts[1])
	if host == "" || port == "" {
		return "", "", fmt.Errorf("invalid host or port in %q", t)
	}
	pn, convErr := strconv.Atoi(port)
	if convErr != nil || pn < 1 || pn > 65535 {
		return "", "", fmt.Errorf("invalid port %q", port)
	}
	return host, port, nil
}

func tcpProbe(host, port string, timeout time.Duration) error {
	address := net.JoinHostPort(host, port)
	conn, err := net.DialTimeout("tcp", address, timeout)
	if err != nil {
		return err
	}
	_ = conn.Close()
	return nil
}

func dialWhileProbing(rawTarget, host, port string, timeout time.Duration, sessionID string, dtmfGapMs int, postDtmfDelayMs int) error {
	probeErrCh := make(chan error, 1)
	go func() {
		probeErrCh <- tcpProbe(host, port, timeout)
	}()

	// Always play tone-short + DTMF for received ATDT digits/characters.
	if err := playDialToneAndDigits(rawTarget, sessionID, dtmfGapMs); err != nil {
		return fmt.Errorf("dial tone/dtmf failed: %w", err)
	}
	if postDtmfDelayMs > 0 {
		time.Sleep(time.Duration(postDtmfDelayMs) * time.Millisecond)
	}

	probeErr := <-probeErrCh
	if probeErr != nil {
		return fmt.Errorf("tcp probe timeout/reject: %w", probeErr)
	}
	return nil
}

func playDialToneAndDigits(rawTarget, sessionID string, dtmfGapMs int) error {
	log.Printf("bridge[%s]: playing tone-short+digits for %q", sessionID, rawTarget)
	seq := make([]string, 0, 2+len(rawTarget))
	seq = append(seq, "tone-short.wav")
	seq = append(seq, buildDialToneList(rawTarget)...)
	if dtmfGapMs <= 0 {
		return playSoundSequence(seq, "tone-short+digits", sessionID)
	}
	combined, err := buildConcatenatedEmbeddedWavWithGap(seq, dtmfGapMs)
	if err == nil {
		return playWavBytes(combined, "tone-short+digits")
	}
	log.Printf("bridge[%s]: single-process sequence playback fallback for tone-short+digits failed: %v", sessionID, err)
	for i, name := range seq {
		if err := playEmbeddedSound(name); err != nil {
			return fmt.Errorf("play sequence component %q: %w", name, err)
		}
		if i < len(seq)-1 {
			time.Sleep(time.Duration(dtmfGapMs) * time.Millisecond)
		}
	}
	return nil
}

func playRingingAndModem(sessionID string) error {
	log.Printf("bridge[%s]: playing ringing+modem", sessionID)
	return playSoundSequence([]string{"ringing.wav", "modem.wav"}, "ringing+modem", sessionID)
}

func playBusyTones(sessionID string, repeat int, gapMs int) {
	if err := playSoundRepeated("busy.wav", repeat, sessionID, gapMs); err != nil {
		log.Printf("bridge[%s]: busy tone playback failed: %v", sessionID, err)
	}
}

func playSoundRepeated(name string, repeat int, sessionID string, gapMs int) error {
	if repeat <= 1 {
		return playEmbeddedSound(name)
	}
	if gapMs > 0 {
		seq := make([]string, repeat)
		for i := range seq {
			seq[i] = name
		}
		combined, err := buildConcatenatedEmbeddedWavWithGap(seq, gapMs)
		if err == nil {
			return playWavBytes(combined, name)
		}
		log.Printf("bridge[%s]: single-process repeated+gap playback fallback for %s failed: %v", sessionID, name, err)
		for i := 0; i < repeat; i++ {
			if err := playEmbeddedSound(name); err != nil {
				return fmt.Errorf("play %s at %d/%d: %w", name, i+1, repeat, err)
			}
			if i < repeat-1 {
				time.Sleep(time.Duration(gapMs) * time.Millisecond)
			}
		}
		return nil
	}
	combinedErr := playRepeatedEmbeddedSound(name, repeat)
	if combinedErr == nil {
		return nil
	}
	log.Printf("bridge[%s]: single-process repeated playback fallback for %s failed: %v", sessionID, name, combinedErr)
	for i := 0; i < repeat; i++ {
		if err := playEmbeddedSound(name); err != nil {
			return fmt.Errorf("play %s at %d/%d: %w", name, i+1, repeat, err)
		}
	}
	return nil
}

func playSoundSequence(names []string, label, sessionID string) error {
	combined, err := buildConcatenatedEmbeddedWav(names)
	if err == nil {
		return playWavBytes(combined, label)
	}
	log.Printf("bridge[%s]: single-process sequence playback fallback for %s failed: %v", sessionID, label, err)
	for _, name := range names {
		if err := playEmbeddedSound(name); err != nil {
			return fmt.Errorf("play sequence component %q: %w", name, err)
		}
	}
	return nil
}

func buildDialToneList(rawTarget string) []string {
	tones := make([]string, 0, len(rawTarget))
	for _, r := range rawTarget {
		switch r {
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
			tones = append(tones, string(r)+".wav")
		case '*':
			tones = append(tones, "star.wav")
		case '#':
			tones = append(tones, "hash.wav")
		}
	}
	return tones
}

func playEmbeddedSound(name string) error {
	data, ok := embeddedSounds[name]
	if !ok {
		return fmt.Errorf("embedded sound %q not found", name)
	}
	return playWavBytes(data, name)
}

func playRepeatedEmbeddedSound(name string, repeat int) error {
	data, ok := embeddedSounds[name]
	if !ok {
		return fmt.Errorf("embedded sound %q not found", name)
	}
	combined, err := buildRepeatedWav(data, repeat)
	if err != nil {
		return err
	}
	return playWavBytes(combined, name)
}

func playWavBytes(data []byte, label string) error {
	tmp, err := os.CreateTemp("", "iyagi-sound-*.wav")
	if err != nil {
		return fmt.Errorf("create temp wav: %w", err)
	}
	tmpPath := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return fmt.Errorf("write temp wav %q: %w", label, err)
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("close temp wav %q: %w", label, err)
	}
	defer os.Remove(tmpPath)

	if err := playSoundFile(tmpPath); err != nil {
		return fmt.Errorf("play %q: %w", label, err)
	}
	return nil
}

func buildRepeatedWav(src []byte, repeat int) ([]byte, error) {
	if repeat <= 1 {
		out := make([]byte, len(src))
		copy(out, src)
		return out, nil
	}
	if len(src) < 12 || string(src[:4]) != "RIFF" || string(src[8:12]) != "WAVE" {
		return nil, fmt.Errorf("not a RIFF/WAVE file")
	}

	var dataOffset int = -1
	var dataSize int
	offset := 12
	for offset+8 <= len(src) {
		chunkID := string(src[offset : offset+4])
		chunkSize := int(binary.LittleEndian.Uint32(src[offset+4 : offset+8]))
		chunkDataStart := offset + 8
		chunkDataEnd := chunkDataStart + chunkSize
		if chunkDataEnd > len(src) {
			return nil, fmt.Errorf("invalid chunk bounds for %s", chunkID)
		}
		if chunkID == "data" {
			dataOffset = chunkDataStart
			dataSize = chunkSize
			// For safe rewriting, require data chunk to be the final chunk.
			paddedEnd := chunkDataEnd
			if chunkSize%2 == 1 {
				paddedEnd++
			}
			if paddedEnd != len(src) {
				return nil, fmt.Errorf("data chunk not final")
			}
			break
		}
		offset = chunkDataEnd
		if chunkSize%2 == 1 {
			offset++
		}
	}
	if dataOffset < 0 || dataSize <= 0 {
		return nil, fmt.Errorf("missing/empty data chunk")
	}

	header := make([]byte, dataOffset)
	copy(header, src[:dataOffset])
	payload := src[dataOffset : dataOffset+dataSize]
	totalDataSize := dataSize * repeat
	out := make([]byte, 0, len(header)+totalDataSize+1)
	out = append(out, header...)
	for i := 0; i < repeat; i++ {
		out = append(out, payload...)
	}
	if totalDataSize%2 == 1 {
		out = append(out, 0x00)
	}

	// Update chunk sizes (little-endian): RIFF size at offset 4, data size at offset (dataOffset-4).
	binary.LittleEndian.PutUint32(out[4:8], uint32(len(out)-8))
	binary.LittleEndian.PutUint32(out[dataOffset-4:dataOffset], uint32(totalDataSize))
	return out, nil
}

func buildConcatenatedEmbeddedWav(names []string) ([]byte, error) {
	if len(names) == 0 {
		return nil, fmt.Errorf("empty sequence")
	}
	var refFmt []byte
	payload := make([]byte, 0, 4096)
	for _, name := range names {
		data, ok := embeddedSounds[name]
		if !ok {
			return nil, fmt.Errorf("embedded sound %q not found", name)
		}
		fmtChunk, wavData, err := parseWavFmtAndData(data)
		if err != nil {
			return nil, fmt.Errorf("parse %q: %w", name, err)
		}
		if refFmt == nil {
			refFmt = fmtChunk
		} else if string(refFmt) != string(fmtChunk) {
			return nil, fmt.Errorf("incompatible WAV format for %q", name)
		}
		payload = append(payload, wavData...)
	}
	return buildWavFromFmtAndData(refFmt, payload), nil
}

func buildConcatenatedEmbeddedWavWithGap(names []string, gapMs int) ([]byte, error) {
	if len(names) == 0 {
		return nil, fmt.Errorf("empty sequence")
	}
	var refFmt []byte
	payload := make([]byte, 0, 4096)
	for i, name := range names {
		data, ok := embeddedSounds[name]
		if !ok {
			return nil, fmt.Errorf("embedded sound %q not found", name)
		}
		fmtChunk, wavData, err := parseWavFmtAndData(data)
		if err != nil {
			return nil, fmt.Errorf("parse %q: %w", name, err)
		}
		if refFmt == nil {
			refFmt = fmtChunk
		} else if string(refFmt) != string(fmtChunk) {
			return nil, fmt.Errorf("incompatible WAV format for %q", name)
		}
		payload = append(payload, wavData...)
		if gapMs > 0 && i < len(names)-1 {
			silence, err := buildSilencePCM(refFmt, gapMs)
			if err != nil {
				return nil, fmt.Errorf("build silence gap: %w", err)
			}
			payload = append(payload, silence...)
		}
	}
	return buildWavFromFmtAndData(refFmt, payload), nil
}

func buildSilencePCM(fmtChunk []byte, gapMs int) ([]byte, error) {
	if gapMs <= 0 {
		return nil, nil
	}
	if len(fmtChunk) < 16 {
		return nil, fmt.Errorf("fmt chunk too short")
	}
	audioFormat := binary.LittleEndian.Uint16(fmtChunk[0:2])
	if audioFormat != 1 {
		return nil, fmt.Errorf("only PCM format is supported")
	}
	sampleRate := int(binary.LittleEndian.Uint32(fmtChunk[4:8]))
	blockAlign := int(binary.LittleEndian.Uint16(fmtChunk[12:14]))
	if sampleRate <= 0 || blockAlign <= 0 {
		return nil, fmt.Errorf("invalid sample rate or block align")
	}
	sampleCount := sampleRate * gapMs / 1000
	if sampleCount <= 0 {
		sampleCount = 1
	}
	return make([]byte, sampleCount*blockAlign), nil
}

func parseWavFmtAndData(src []byte) ([]byte, []byte, error) {
	if len(src) < 12 || string(src[:4]) != "RIFF" || string(src[8:12]) != "WAVE" {
		return nil, nil, fmt.Errorf("not RIFF/WAVE")
	}
	offset := 12
	var fmtChunk []byte
	var dataChunk []byte
	for offset+8 <= len(src) {
		chunkID := string(src[offset : offset+4])
		chunkSize := int(binary.LittleEndian.Uint32(src[offset+4 : offset+8]))
		chunkDataStart := offset + 8
		chunkDataEnd := chunkDataStart + chunkSize
		if chunkDataEnd > len(src) {
			return nil, nil, fmt.Errorf("invalid chunk bounds for %s", chunkID)
		}
		switch chunkID {
		case "fmt ":
			fmtChunk = append([]byte(nil), src[chunkDataStart:chunkDataEnd]...)
		case "data":
			dataChunk = append([]byte(nil), src[chunkDataStart:chunkDataEnd]...)
		}
		offset = chunkDataEnd
		if chunkSize%2 == 1 {
			offset++
		}
	}
	if len(fmtChunk) == 0 || len(dataChunk) == 0 {
		return nil, nil, fmt.Errorf("missing fmt/data chunk")
	}
	return fmtChunk, dataChunk, nil
}

func buildWavFromFmtAndData(fmtChunk, dataChunk []byte) []byte {
	size := 12 + 8 + len(fmtChunk) + 8 + len(dataChunk)
	if len(dataChunk)%2 == 1 {
		size++
	}
	out := make([]byte, 0, size)
	out = append(out, []byte("RIFF")...)
	out = append(out, 0, 0, 0, 0)
	out = append(out, []byte("WAVE")...)
	out = append(out, []byte("fmt ")...)
	fmtSize := make([]byte, 4)
	binary.LittleEndian.PutUint32(fmtSize, uint32(len(fmtChunk)))
	out = append(out, fmtSize...)
	out = append(out, fmtChunk...)
	out = append(out, []byte("data")...)
	dataSize := make([]byte, 4)
	binary.LittleEndian.PutUint32(dataSize, uint32(len(dataChunk)))
	out = append(out, dataSize...)
	out = append(out, dataChunk...)
	if len(dataChunk)%2 == 1 {
		out = append(out, 0x00)
	}
	binary.LittleEndian.PutUint32(out[4:8], uint32(len(out)-8))
	return out
}

func playSoundFile(path string) error {
	switch runtime.GOOS {
	case "windows":
		return runFirstAvailablePlayer([][]string{
			{
				"powershell",
				"-NoProfile",
				"-NonInteractive",
				"-Command",
				fmt.Sprintf(`(New-Object Media.SoundPlayer '%s').PlaySync()`, filepath.ToSlash(path)),
			},
		})
	case "darwin":
		return runFirstAvailablePlayer([][]string{
			{"afplay", path},
		})
	default:
		return runFirstAvailablePlayer([][]string{
			{"aplay", "-q", path},
			{"paplay", path},
			{"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path},
			{"play", "-q", path},
		})
	}
}

func runFirstAvailablePlayer(candidates [][]string) error {
	var checked []string
	for _, args := range candidates {
		if len(args) == 0 {
			continue
		}
		bin := args[0]
		checked = append(checked, bin)
		if _, err := exec.LookPath(bin); err != nil {
			continue
		}
		cmd := exec.Command(bin, args[1:]...)
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("%s failed: %w", strings.Join(args, " "), err)
		}
		return nil
	}
	return fmt.Errorf("no usable audio player found (checked: %s)", strings.Join(checked, ", "))
}

func buildOutboundCommand(template, sshUser, host, port string) (string, []string, error) {
	resolvedUser, resolvedHost, err := resolveSSHUserAndHost(sshUser, host)
	if err != nil {
		return "", nil, err
	}
	userHost := resolvedHost
	if resolvedUser != "" {
		userHost = resolvedUser + "@" + resolvedHost
	}
	cmdline := template
	cmdline = strings.ReplaceAll(cmdline, "{host}", resolvedHost)
	cmdline = strings.ReplaceAll(cmdline, "{port}", port)
	cmdline = strings.ReplaceAll(cmdline, "{userhost}", userHost)
	cmdline = strings.TrimSpace(cmdline)
	parts := strings.Fields(cmdline)
	if len(parts) == 0 {
		return "", nil, fmt.Errorf("empty BRIDGE_CMD_TEMPLATE after substitution")
	}
	return parts[0], parts[1:], nil
}

func logOutboundDialDebug(sessionID, sshUser, host, port, execPath string, execArgs []string) {
	trimmedUser := strings.TrimSpace(sshUser)
	resolvedUser, resolvedHost, resolveErr := resolveSSHUserAndHost(sshUser, host)
	userHost := resolvedHost
	if resolvedUser != "" {
		userHost = resolvedUser + "@" + resolvedHost
	}
	log.Printf(
		"bridge[%s]: ssh-debug user(raw)=%q user(trimmed)=%q host(raw)=%q host(resolved)=%q port=%q userhost=%q",
		sessionID,
		sshUser,
		trimmedUser,
		host,
		resolvedHost,
		port,
		userHost,
	)
	if resolveErr != nil {
		log.Printf("bridge[%s]: ssh-debug user/host resolve error: %v", sessionID, resolveErr)
	}
	if sshUser != trimmedUser {
		log.Printf("bridge[%s]: ssh-debug user has leading/trailing whitespace bytes: %s", sessionID, debugBytes([]byte(sshUser)))
	}
	if strings.ContainsAny(trimmedUser, "@:/ \t\r\n") {
		log.Printf("bridge[%s]: ssh-debug user contains suspicious characters: %q", sessionID, trimmedUser)
	}
	argv := append([]string{execPath}, execArgs...)
	quoted := make([]string, 0, len(argv))
	for _, token := range argv {
		quoted = append(quoted, strconv.QuoteToASCII(token))
	}
	log.Printf("bridge[%s]: ssh-debug argv=%s", sessionID, strings.Join(quoted, " "))
}

func resolveSSHUserAndHost(sshUser, dialHost string) (user, host string, err error) {
	host = strings.TrimSpace(dialHost)
	if host == "" {
		return "", "", fmt.Errorf("empty dial host")
	}
	user = strings.TrimSpace(sshUser)
	if user == "" {
		return "", host, nil
	}
	if strings.Contains(user, "@") {
		parts := strings.Split(user, "@")
		if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
			return "", "", fmt.Errorf("invalid BRIDGE_SSH_USER %q; expected user or user@host", sshUser)
		}
		user = strings.TrimSpace(parts[0])
		host = strings.TrimSpace(parts[1])
	}
	return user, host, nil
}

func writeModemResponse(conn net.Conn, msg string) {
	if _, err := io.WriteString(conn, msg+"\r\n"); err != nil {
		log.Printf("bridge: write modem response %q failed: %v", msg, err)
		return
	}
}

func getenv(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}

func parseBoolEnv(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func applyClientEncodingReader(src io.Reader, mode string) io.Reader {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "off", "none", "utf8":
		return src
	case "euc-kr", "euckr", "cp949", "wansung":
		// Korean.EUCKR decoder covers common Korean legacy terminal encodings
		// used by DOS apps and converts to UTF-8 for modern SSH services.
		return transform.NewReader(src, korean.EUCKR.NewDecoder())
	default:
		return src
	}
}

func applyServerEncodingReader(src io.Reader, mode string) io.Reader {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "off", "none", "utf8":
		return src
	case "euc-kr", "euckr", "cp949", "wansung":
		// Convert UTF-8 output from SSH server to legacy Korean bytes.
		// ReplaceUnsupported avoids breaking the stream on non-representable runes.
		enc := textencoding.ReplaceUnsupported(korean.EUCKR.NewEncoder())
		return transform.NewReader(src, enc)
	default:
		return src
	}
}

func maybeRepairServerMojibakeReader(src io.Reader, enabled bool) io.Reader {
	if !enabled {
		return src
	}
	pr, pw := io.Pipe()
	go func() {
		defer pw.Close()
		buf := make([]byte, 4096)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				fixed := repairUTF8MojibakeChunk(buf[:n])
				if _, werr := pw.Write(fixed); werr != nil {
					return
				}
			}
			if err != nil {
				if err != io.EOF {
					_ = pw.CloseWithError(err)
				}
				return
			}
		}
	}()
	return pr
}

func maybeRewriteANSIResetReader(src io.Reader, enabled bool) io.Reader {
	if !enabled {
		return src
	}
	pr, pw := io.Pipe()
	go func() {
		defer pw.Close()
		pattern := []byte{0x1b, '[', '0', 'm'}
		replacement := []byte{0x1b, '[', '0', ';', '1', ';', '3', '7', ';', '4', '0', 'm'}

		buf := make([]byte, 4096)
		carry := make([]byte, 0, len(pattern)-1)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				joined := append(carry, buf[:n]...)
				keep := ansiPatternCarry(joined, pattern)
				processEnd := len(joined) - keep
				if processEnd > 0 {
					processed := bytes.ReplaceAll(joined[:processEnd], pattern, replacement)
					if _, werr := pw.Write(processed); werr != nil {
						return
					}
				}
				carry = append(carry[:0], joined[processEnd:]...)
			}
			if err != nil {
				if len(carry) > 0 {
					processed := bytes.ReplaceAll(carry, pattern, replacement)
					if _, werr := pw.Write(processed); werr != nil {
						return
					}
				}
				if err != io.EOF {
					_ = pw.CloseWithError(err)
				}
				return
			}
		}
	}()
	return pr
}

func ansiPatternCarry(data, pattern []byte) int {
	maxKeep := len(pattern) - 1
	if maxKeep <= 0 || len(data) == 0 {
		return 0
	}
	if len(data) < maxKeep {
		maxKeep = len(data)
	}
	for k := maxKeep; k > 0; k-- {
		if bytes.Equal(data[len(data)-k:], pattern[:k]) {
			return k
		}
	}
	return 0
}

func repairUTF8MojibakeChunk(p []byte) []byte {
	if len(p) == 0 || !utf8.Valid(p) {
		return p
	}
	runes := []rune(string(p))
	var b strings.Builder
	for i := 0; i < len(runes); {
		if runes[i] > 0xFF {
			b.WriteRune(runes[i])
			i++
			continue
		}
		j := i
		hasHigh := false
		for j < len(runes) && runes[j] <= 0xFF {
			if runes[j] >= 0x80 {
				hasHigh = true
			}
			j++
		}
		segment := runes[i:j]
		if hasHigh {
			raw := make([]byte, len(segment))
			for k, r := range segment {
				raw[k] = byte(r)
			}
			if utf8.Valid(raw) {
				decoded := string(raw)
				if containsNonASCII(decoded) {
					b.WriteString(decoded)
					i = j
					continue
				}
			}
		}
		b.WriteString(string(segment))
		i = j
	}
	return []byte(b.String())
}

func containsNonASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			return true
		}
	}
	return false
}
