// Theme toggle
function toggleTheme() {
  const html = document.documentElement;
  const btn = document.querySelector('.theme-toggle');
  if (html.getAttribute('data-theme') === 'dark') {
    html.removeAttribute('data-theme');
    btn.textContent = '🌙';
    localStorage.setItem('theme', 'light');
  } else {
    html.setAttribute('data-theme', 'dark');
    btn.textContent = '☀️';
    localStorage.setItem('theme', 'dark');
  }
}

// Load theme: saved preference > system preference > light
(function() {
  const saved = localStorage.getItem('theme');
  const btn = document.querySelector('.theme-toggle');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

  const useDark = saved === 'dark' || (saved === null && prefersDark);
  if (useDark) {
    document.documentElement.setAttribute('data-theme', 'dark');
    btn.textContent = '☀️';
  }
})();

// Floating emojis
(function() {
  const emojiConfig = [
    { char: '☎️', native: 'ltr' },
    { char: '💬', native: 'ltr' },
    { char: '🗨️', native: 'rtl' },
    { char: '🖥️', native: 'ltr' },
    { char: '📦', native: 'ltr' },
    { char: '🔌', native: 'ltr' },
  ];

  const container = document.getElementById('emojiContainer');
  if (!container) {
    return;
  }

  function createEmoji(forceDirection) {
    const emoji = document.createElement('span');
    const pick = emojiConfig[Math.floor(Math.random() * emojiConfig.length)];
    emoji.textContent = pick.char;

    const direction = forceDirection || (Math.random() > 0.5 ? 'ltr' : 'rtl');
    const needsFlip = direction !== pick.native;
    emoji.className = 'floating-emoji ' + direction + (needsFlip ? ' flipped' : '');

    const topPos = Math.random() * 80 + 10;
    emoji.style.top = topPos + '%';

    const duration = 5 + Math.random() * 3;
    emoji.style.animationDuration = duration + 's';

    const size = 1.2 + Math.random() * 0.8;
    emoji.style.fontSize = size + 'rem';

    container.appendChild(emoji);
    setTimeout(() => emoji.remove(), duration * 1000);
  }

  let phase = 0;
  const busyDuration = 6000;
  const quietDuration = 8000;

  function getSpawnDelay() {
    if (phase === 0) {
      return 800 + Math.random() * 400;
    }
    return 3000 + Math.random() * 2000;
  }

  function scheduleNext() {
    const delay = getSpawnDelay();
    setTimeout(() => {
      createEmoji();
      scheduleNext();
    }, delay);
  }

  function cyclePhase() {
    phase = (phase + 1) % 2;
    const duration = phase === 0 ? busyDuration : quietDuration;
    setTimeout(cyclePhase, duration);
  }

  for (let i = 0; i < 4; i++) {
    setTimeout(() => createEmoji(), i * 300);
  }
  scheduleNext();
  setTimeout(cyclePhase, busyDuration);
})();
