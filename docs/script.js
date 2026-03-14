window.dataLayer = window.dataLayer || [];
function gtag() {
  window.dataLayer.push(arguments);
}
gtag("js", new Date());
gtag("config", "G-4N0G7MTYN8");

function initScreenshotModal() {
  const modal = document.getElementById("screenshotsModal");
  const openBtn = document.getElementById("openScreenshots");
  const closeTargets = document.querySelectorAll("[data-close-modal]");

  if (!modal || !openBtn) {
    return;
  }

  function openModal() {
    modal.classList.add("is-open");
    modal.setAttribute("aria-hidden", "false");
  }

  function closeModal() {
    modal.classList.remove("is-open");
    modal.setAttribute("aria-hidden", "true");
  }

  openBtn.addEventListener("click", openModal);
  closeTargets.forEach(function (el) {
    el.addEventListener("click", closeModal);
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      closeModal();
    }
  });
}

function initIntroMediaChain() {
  const modemSound = document.getElementById("modemSound");
  const introVideo = document.getElementById("introVideo");

  if (!modemSound || !introVideo) {
    return;
  }

  // Hard guard: never initialize this chain more than once per page lifecycle.
  if (modemSound.dataset.chainInitialized === "1") {
    return;
  }
  modemSound.dataset.chainInitialized = "1";

  // Explicitly disable looping to avoid unexpected repeat playback.
  modemSound.loop = false;
  introVideo.loop = false;

  if (modemSound.readyState === 0) {
    modemSound.load();
  }

  modemSound.addEventListener(
    "ended",
    function () {
      if (introVideo.dataset.autoPlayedOnce === "1") {
        return;
      }
      introVideo.dataset.autoPlayedOnce = "1";
      introVideo.currentTime = 0;
      introVideo.play().catch(function () {});
    },
    { once: true }
  );

  let started = false;
  const unlockEvents = ["pointerdown", "keydown", "touchstart"];

  function removeUnlockHandlers() {
    unlockEvents.forEach(function (eventName) {
      document.removeEventListener(eventName, startModemAndChain);
    });
  }

  function startModemAndChain() {
    if (started || modemSound.dataset.autoPlayedOnce === "1") {
      return;
    }
    started = true;
    modemSound.dataset.autoPlayedOnce = "1";
    removeUnlockHandlers();
    modemSound.currentTime = 0;
    modemSound.play().catch(function () {});
  }

  // First try: play immediately on render.
  if (modemSound.dataset.autoPlayedOnce !== "1") {
    modemSound.dataset.autoPlayedOnce = "1";
    modemSound.currentTime = 0;
    modemSound.play().catch(function () {
      modemSound.dataset.autoPlayedOnce = "0";
    // Browser autoplay policy blocked audio; retry once on first interaction.
      unlockEvents.forEach(function (eventName) {
        document.addEventListener(eventName, startModemAndChain, { once: true, passive: true });
      });
    });
  }
}

document.addEventListener("DOMContentLoaded", function () {
  initScreenshotModal();
  initIntroMediaChain();
});
