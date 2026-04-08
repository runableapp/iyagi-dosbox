window.dataLayer = window.dataLayer || [];
function gtag() {
  window.dataLayer.push(arguments);
}
gtag("js", new Date());
gtag("config", "G-4N0G7MTYN8");

const I18N = {
  ko: {
    htmlLang: "ko",
    pageTitle: "이야기 도스박스",
    pageDescription:
      "이야기 5.3을 도스박스와 브리지(bridge) 프로그램으로 비비에스(BBS)에 연결하는 멀티플랫폼 패키지 프로젝트",
    langSwitchAria: "언어 선택",
    supportFloatBtn: "♡ 프로젝트 후원하기",
    supportFloatAria: "프로젝트 후원",
    heroTopImageAlt: "이야기 도스박스 레트로 화면",
    heroTitle: "☎ 이야기 도스박스",
    heroTagline: "도스 통신 감성을 그대로 살려 비비에스(BBS)로 연결하는 실행 환경을 제공하여 추억을 되살립니다.",
    githubBtnText: "GitHub 저장소 보기",
    githubBtnAria: "GitHub 저장소 보기",
    releaseBtnText: "💾 프로그램 다운받기",
    releaseBtnAria: "💾 프로그램 다운받기",
    aboutTitle: "◆ \"이야기 도스박스\"가 무엇인가요?",
    aboutP1:
      "<span class=\"iyagi-word-wrap\"><span class=\"iyagi-word\">이야기" +
      "<sup class=\"iyagi-word-ref\"><a href=\"https://ko.wikipedia.org/wiki/%EC%9D%B4%EC%95%BC%EA%B8%B0_(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">1</a><span class=\"iyagi-word-sep\">,</span><a href=\"https://namu.wiki/w/%EC%9D%B4%EC%95%BC%EA%B8%B0(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">2</a></sup></span></span>" +
      "는 원래 모뎀 다이얼업 통신용 도스 프로그램입니다. 이 프로젝트는 도스박스 가상 모뎀과 브리지(bridge)를 이용해 기존 조작감을 유지하면서 <strong>비비에스(BBS)</strong>로 접속할 수 있게 묶어 둔 실행 패키지입니다.",
    aboutP2:
      "그 시절 접속음과 화면을 보면 괜히 가슴이 뛰지 않나요? 이야기 도스박스는 그 추억을 지금 다시 꺼내 즐길 수 있도록, 윈도우/맥OS/리눅스에서 바로 실행되는 형태로 준비했습니다.",
    aboutP3:
      "필요한 건 하나뿐입니다. 다운로드해서 간단히 설치하고 실행만 하면, 금세 그 시절로 돌아가 다시 즐길 수 있습니다.",
    introVideoCredit: "<영화 '접속', 1997년>",
    introVideoReplay: "영화 다시 보기",
    howTitle: "▣ 어떻게 동작하나요?",
    flowDiagramAria: "동작 흐름 다이어그램",
    flowNodeIyagi: "이야기",
    flowNodeDosbox: "도스박스",
    flowNodeBridge: "브리지(bridge)",
    flowNodeBbs: "비비에스(BBS)",
    flowCaption: "실행하면 위 순서로 연결되어, 익숙한 화면 감성 그대로 접속을 즐길 수 있습니다.",
    featuresTitle: "★ 주요 기능",
    feature1Title: "■ 주요 플랫폼 지원",
    feature1Body: "리눅스(AppImage), 윈도우(설치 프로그램), 맥OS(DMG)를 지원합니다.",
    feature2Title: "▤ 도스 감성 유지",
    feature2Body: "이야기 원본 실행 흐름을 유지하면서 비비에스(BBS)로 연결합니다.",
    feature3Title: "※ 자동 설정 패치",
    feature3Body: "<code>I.CNF</code>, <code>I.TEL</code> 자동 패치로 브리지 접속 항목/경로를 맞춰줍니다.",
    feature4Title: "☏ 모뎀 사운드 재현",
    feature4Body: "접속 시 특유의 모뎀 다이얼/연결음을 들을 수 있어 당시 사용 경험을 최대한 유지합니다.",
    feature5Title: "※ 완성형 ↔ UTF-8 변환",
    feature5Body: "브리지(bridge)에서 완성형(EUC-KR 계열)과 UTF-8 간 텍스트 변환을 처리해 한글 깨짐을 줄입니다.",
    feature6Title: "◇ 런타임 정리",
    feature6Body: "브리지 프로세스 시작/종료를 런처에서 안전하게 관리합니다.",
    feature7Title: "◈ 도스박스 최적화",
    feature7Body: "스케일러/창 크기 등 실행 설정을 프로젝트 환경에 맞춰 조정했습니다.",
    screenshotsTitle: "▦ 스크린샷",
    screenshotsDesc: "아래에는 대표 화면 1장만 표시됩니다. 나머지 예시 화면은 팝업에서 확인할 수 있습니다.",
    screenshotMainAlt: "이야기 도스박스 대표 스크린샷",
    screenshotCaption: "대표 실행 화면",
    openScreenshots: "다른 스크린샷 보기",
    videoTitle: "▶ 실행 영상",
    videoDesc: "실행 영상 미리보기",
    docsTitle: "§ 문서",
    docsManualLink: "이야기 5.3 사용자 매뉴얼 (한국어)",
    donationTitle: "♡ 프로젝트 후원",
    donationDesc: "프로젝트가 도움이 되었다면 후원으로 개발 지속에 힘을 보태주세요.",
    donationBtn: "프로젝트 후원하기",
    donationBtnAria: "프로젝트 후원",
    creditsTitle: "§ 크레딧",
    creditIyagiTeam: "이야기 팀",
    creditFontLink: "이야기 굵은체 폰트 (IyagiGGC)",
    footerLogoAlt: "Runable.app 로고",
    licenseLinkText: "폴리폼 비상업라이센스",
    modalAria: "스크린샷 모음",
    modalCloseBtn: "닫기",
    modalCloseAria: "팝업 닫기",
    modalTitle: "추가 스크린샷",
    modalImage1Alt: "이야기 도스박스 스크린샷 1",
    modalImage2Alt: "이야기 도스박스 스크린샷 2"
  },
  en: {
    htmlLang: "en",
    pageTitle: "Iyagi DOSBox",
    pageDescription:
      "A multi-platform package that connects Iyagi 5.3 to BBS through DOSBox and a bridge.",
    langSwitchAria: "Language selector",
    supportFloatBtn: "♡ Support This Project",
    supportFloatAria: "Support this project",
    heroTopImageAlt: "Iyagi DOSBox retro screen",
    heroTitle: "☎ Iyagi DOSBox",
    heroTagline: "Relive the classic dial-up BBS feeling with a ready-to-run package.",
    githubBtnText: "View on GitHub",
    githubBtnAria: "View GitHub repository",
    releaseBtnText: "💾 Download Program",
    releaseBtnAria: "💾 Download program",
    aboutTitle: "◆ What is \"Iyagi DOSBox\"?",
    aboutP1:
      "<span class=\"iyagi-word-wrap\"><span class=\"iyagi-word\">IYAGI" +
      "<sup class=\"iyagi-word-ref\"><a href=\"https://ko.wikipedia.org/wiki/%EC%9D%B4%EC%95%BC%EA%B8%B0_(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">1</a><span class=\"iyagi-word-sep\">,</span><a href=\"https://namu.wiki/w/%EC%9D%B4%EC%95%BC%EA%B8%B0(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">2</a></sup></span></span>" +
      " was originally a DOS modem dial-up communication program. This project bundles DOSBox virtual modem and a bridge to connect to <strong>BBS</strong> while preserving the original interaction style.",
    aboutP2:
      "Remember that connection sound and screen from back then? Iyagi DOSBox lets you enjoy that nostalgia again on Windows, macOS, and Linux.",
    aboutP3:
      "Just download, install, and run. You can jump back to that era in minutes.",
    introVideoCredit: "<Movie \"The Contact\", 1997>",
    introVideoReplay: "Watch on Viki",
    howTitle: "▣ How does it work?",
    flowDiagramAria: "Connection flow diagram",
    flowNodeIyagi: "IYAGI",
    flowNodeDosbox: "DOSBox",
    flowNodeBridge: "Bridge",
    flowNodeBbs: "BBS",
    flowCaption: "At runtime, it connects in this order so you can keep the familiar retro workflow.",
    featuresTitle: "★ Key Features",
    feature1Title: "■ Multi-platform support",
    feature1Body: "Supports Linux (AppImage), Windows (installer), and macOS (DMG).",
    feature2Title: "▤ Classic DOS experience",
    feature2Body: "Keeps the original Iyagi flow while connecting to BBS.",
    feature3Title: "※ Auto configuration patch",
    feature3Body: "Automatically patches <code>I.CNF</code> and <code>I.TEL</code> to set bridge connection entries and paths.",
    feature4Title: "☏ Modem sound recreation",
    feature4Body: "Replays classic modem dial/connect sounds for an authentic experience.",
    feature5Title: "※ Wansung ↔ UTF-8 conversion",
    feature5Body: "The bridge handles Wansung (EUC-KR family) to UTF-8 conversion to reduce Korean text corruption.",
    feature6Title: "◇ Runtime process handling",
    feature6Body: "Launcher safely starts and stops the bridge process.",
    feature7Title: "◈ DOSBox tuning",
    feature7Body: "Display scaling and window settings are tuned for this package.",
    screenshotsTitle: "▦ Screenshots",
    screenshotsDesc: "One representative screenshot is shown below. Open the popup for more examples.",
    screenshotMainAlt: "Iyagi DOSBox main screenshot",
    screenshotCaption: "Representative runtime screen",
    openScreenshots: "View More Screenshots",
    videoTitle: "▶ Demo Video",
    videoDesc: "Preview video",
    docsTitle: "§ Documentation",
    docsManualLink: "Iyagi 5.3 User Manual (Korean)",
    donationTitle: "♡ Support the Project",
    donationDesc: "If this project helped you, your support helps continued development.",
    donationBtn: "Support This Project",
    donationBtnAria: "Support this project",
    creditsTitle: "§ Credits",
    creditIyagiTeam: "Iyagi Team",
    creditFontLink: "Iyagi Bold Font (IyagiGGC)",
    footerLogoAlt: "Runable.app logo",
    licenseLinkText: "PolyForm Noncommercial License (Korean)",
    modalAria: "Screenshot gallery",
    modalCloseBtn: "Close",
    modalCloseAria: "Close popup",
    modalTitle: "More Screenshots",
    modalImage1Alt: "Iyagi DOSBox screenshot 1",
    modalImage2Alt: "Iyagi DOSBox screenshot 2"
  },
  zh: {
    htmlLang: "zh",
    pageTitle: "Iyagi DOSBox",
    pageDescription:
      "通过 DOSBox 与桥接程序，将 Iyagi 5.3 连接到 BBS 的多平台打包项目。",
    langSwitchAria: "语言选择",
    supportFloatBtn: "♡ 支持项目",
    supportFloatAria: "支持项目",
    heroTopImageAlt: "Iyagi DOSBox 复古界面",
    heroTitle: "☎ Iyagi DOSBox",
    heroTagline: "尽可能还原 DOS 拨号通信手感，并提供可直接连接 BBS 的运行环境。",
    githubBtnText: "查看 GitHub 仓库",
    githubBtnAria: "查看 GitHub 仓库",
    releaseBtnText: "💾 下载程序",
    releaseBtnAria: "💾 下载程序",
    aboutTitle: "◆ 什么是 \"Iyagi DOSBox\"？",
    aboutP1:
      "<span class=\"iyagi-word-wrap\"><span class=\"iyagi-word\">IYAGI" +
      "<sup class=\"iyagi-word-ref\"><a href=\"https://ko.wikipedia.org/wiki/%EC%9D%B4%EC%95%BC%EA%B8%B0_(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">1</a><span class=\"iyagi-word-sep\">,</span><a href=\"https://namu.wiki/w/%EC%9D%B4%EC%95%BC%EA%B8%B0(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">2</a></sup></span></span>" +
      " 原本是用于调制解调器拨号通信的 DOS 程序。本项目将 DOSBox 虚拟调制解调器与桥接程序打包，尽量保留原始操作感并可连接到 <strong>BBS</strong>。",
    aboutP2:
      "听到那时的连接音、看到熟悉画面，心跳是不是会加快？Iyagi DOSBox 让你在 Windows / macOS / Linux 上再次体验那份回忆。",
    aboutP3: "只要下载、简单安装并运行，就能很快回到那个时代。",
    introVideoCredit: "<电影《接触》, 1997>",
    introVideoReplay: "在线观看 (Viki)",
    howTitle: "▣ 工作原理",
    flowDiagramAria: "连接流程图",
    flowNodeIyagi: "IYAGI",
    flowNodeDosbox: "DOSBox",
    flowNodeBridge: "桥接(bridge)",
    flowNodeBbs: "BBS",
    flowCaption: "运行时会按上述顺序连接，保留熟悉的复古操作流程。",
    featuresTitle: "★ 主要功能",
    feature1Title: "■ 多平台支持",
    feature1Body: "支持 Linux (AppImage)、Windows (安装程序)、macOS (DMG)。",
    feature2Title: "▤ 保留 DOS 体验",
    feature2Body: "保持 Iyagi 原始运行流程，并连接到 BBS。",
    feature3Title: "※ 自动配置补丁",
    feature3Body: "自动修补 <code>I.CNF</code> 和 <code>I.TEL</code>，匹配桥接连接项与路径。",
    feature4Title: "☏ 调制解调器音效还原",
    feature4Body: "连接时可听到经典拨号/握手音效，尽量还原当年体验。",
    feature5Title: "※ 完成型 ↔ UTF-8 转换",
    feature5Body: "桥接程序处理完成型(EUC-KR 系)与 UTF-8 的文本转换，减少韩文乱码。",
    feature6Title: "◇ 运行时管理",
    feature6Body: "启动器安全管理桥接进程的启动与退出。",
    feature7Title: "◈ DOSBox 优化",
    feature7Body: "按项目环境调优缩放与窗口等运行设置。",
    screenshotsTitle: "▦ 截图",
    screenshotsDesc: "下方只显示 1 张代表截图，其余示例可在弹窗中查看。",
    screenshotMainAlt: "Iyagi DOSBox 代表截图",
    screenshotCaption: "代表运行画面",
    openScreenshots: "查看其他截图",
    videoTitle: "▶ 演示视频",
    videoDesc: "运行视频预览",
    docsTitle: "§ 文档",
    docsManualLink: "Iyagi 5.3 用户手册（韩语）",
    donationTitle: "♡ 项目赞助",
    donationDesc: "如果本项目对你有帮助，欢迎赞助以支持持续开发。",
    donationBtn: "赞助此项目",
    donationBtnAria: "赞助此项目",
    creditsTitle: "§ 致谢",
    creditIyagiTeam: "Iyagi 团队",
    creditFontLink: "Iyagi 粗体字体 (IyagiGGC)",
    footerLogoAlt: "Runable.app 标志",
    licenseLinkText: "PolyForm 非商业许可（韩语）",
    modalAria: "截图弹窗",
    modalCloseBtn: "关闭",
    modalCloseAria: "关闭弹窗",
    modalTitle: "更多截图",
    modalImage1Alt: "Iyagi DOSBox 截图 1",
    modalImage2Alt: "Iyagi DOSBox 截图 2"
  },
  ja: {
    htmlLang: "ja",
    pageTitle: "Iyagi DOSBox",
    pageDescription:
      "Iyagi 5.3 を DOSBox とブリッジで BBS に接続するマルチプラットフォームパッケージ。",
    langSwitchAria: "言語選択",
    supportFloatBtn: "♡ プロジェクトを支援",
    supportFloatAria: "プロジェクトを支援",
    heroTopImageAlt: "Iyagi DOSBox レトロ画面",
    heroTitle: "☎ Iyagi DOSBox",
    heroTagline: "DOS通信の感覚をそのままに、BBSへ接続できる実行環境を提供します。",
    githubBtnText: "GitHub リポジトリを見る",
    githubBtnAria: "GitHub リポジトリを見る",
    releaseBtnText: "💾 プログラムをダウンロード",
    releaseBtnAria: "💾 プログラムをダウンロード",
    aboutTitle: "◆ 「Iyagi DOSBox」とは？",
    aboutP1:
      "<span class=\"iyagi-word-wrap\"><span class=\"iyagi-word\">IYAGI" +
      "<sup class=\"iyagi-word-ref\"><a href=\"https://ko.wikipedia.org/wiki/%EC%9D%B4%EC%95%BC%EA%B8%B0_(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">1</a><span class=\"iyagi-word-sep\">,</span><a href=\"https://namu.wiki/w/%EC%9D%B4%EC%95%BC%EA%B8%B0(%EC%86%8C%ED%94%84%ED%8A%B8%EC%9B%A8%EC%96%B4)\" target=\"_blank\" rel=\"noopener\" class=\"iyagi-word-link\">2</a></sup></span></span>" +
      " は、もともとモデムのダイヤルアップ通信用 DOS プログラムです。本プロジェクトは DOSBox 仮想モデムとブリッジを組み合わせ、操作感を保ったまま <strong>BBS</strong> に接続できる実行パッケージです。",
    aboutP2:
      "あの接続音と画面を見ると、今でも胸が高鳴りませんか？Iyagi DOSBox はその思い出を Windows / macOS / Linux で再び楽しめるようにしました。",
    aboutP3:
      "必要なのはひとつだけ。ダウンロードして簡単にインストールし、実行するだけです。",
    introVideoCredit: "<映画『接続』, 1997>",
    introVideoReplay: "Vikiで視聴",
    howTitle: "▣ 仕組み",
    flowDiagramAria: "接続フロー図",
    flowNodeIyagi: "IYAGI",
    flowNodeDosbox: "DOSBox",
    flowNodeBridge: "ブリッジ(bridge)",
    flowNodeBbs: "BBS",
    flowCaption: "実行時はこの順で接続され、昔ながらの操作感を保てます。",
    featuresTitle: "★ 主な機能",
    feature1Title: "■ マルチプラットフォーム対応",
    feature1Body: "Linux (AppImage)、Windows (インストーラー)、macOS (DMG) をサポートします。",
    feature2Title: "▤ DOS の感覚を維持",
    feature2Body: "Iyagi 本来の実行フローを維持したまま BBS に接続します。",
    feature3Title: "※ 自動設定パッチ",
    feature3Body: "<code>I.CNF</code> と <code>I.TEL</code> を自動パッチし、ブリッジ接続項目/パスを合わせます。",
    feature4Title: "☏ モデムサウンド再現",
    feature4Body: "接続時に特徴的なモデム音を再現し、当時の体験を最大限維持します。",
    feature5Title: "※ Wansung ↔ UTF-8 変換",
    feature5Body: "ブリッジで Wansung(EUC-KR 系) と UTF-8 の変換を行い、韓国語の文字化けを減らします。",
    feature6Title: "◇ ランタイム整理",
    feature6Body: "ランチャーがブリッジプロセスの起動/終了を安全に管理します。",
    feature7Title: "◈ DOSBox 最適化",
    feature7Body: "スケーラーやウィンドウサイズなどを本プロジェクト向けに調整しています。",
    screenshotsTitle: "▦ スクリーンショット",
    screenshotsDesc: "下には代表画面 1 枚のみ表示されます。その他はポップアップで確認できます。",
    screenshotMainAlt: "Iyagi DOSBox 代表スクリーンショット",
    screenshotCaption: "代表実行画面",
    openScreenshots: "他のスクリーンショットを見る",
    videoTitle: "▶ 実行動画",
    videoDesc: "実行動画プレビュー",
    docsTitle: "§ ドキュメント",
    docsManualLink: "Iyagi 5.3 ユーザーマニュアル（韓国語）",
    donationTitle: "♡ プロジェクト支援",
    donationDesc: "このプロジェクトが役に立ったら、継続開発のためにご支援ください。",
    donationBtn: "プロジェクトを支援する",
    donationBtnAria: "プロジェクトを支援",
    creditsTitle: "§ クレジット",
    creditIyagiTeam: "Iyagi チーム",
    creditFontLink: "Iyagi 太字フォント (IyagiGGC)",
    footerLogoAlt: "Runable.app ロゴ",
    licenseLinkText: "PolyForm 非営利ライセンス（韓国語）",
    modalAria: "スクリーンショット一覧",
    modalCloseBtn: "閉じる",
    modalCloseAria: "ポップアップを閉じる",
    modalTitle: "追加スクリーンショット",
    modalImage1Alt: "Iyagi DOSBox スクリーンショット 1",
    modalImage2Alt: "Iyagi DOSBox スクリーンショット 2"
  }
};

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) {
    el.textContent = value;
  }
}

function setHtml(id, value) {
  const el = document.getElementById(id);
  if (el) {
    el.innerHTML = value;
  }
}

function setAttr(id, attrName, value) {
  const el = document.getElementById(id);
  if (el) {
    el.setAttribute(attrName, value);
  }
}

function applyLanguage(lang) {
  const locale = I18N[lang] || I18N.ko;
  document.documentElement.lang = locale.htmlLang;
  document.title = locale.pageTitle;

  const metaDescription = document.querySelector('meta[name="description"]');
  if (metaDescription) {
    metaDescription.setAttribute("content", locale.pageDescription);
  }

  setAttr("langSwitch", "aria-label", locale.langSwitchAria);

  setText("supportFloatBtn", locale.supportFloatBtn);
  setAttr("supportFloatBtn", "aria-label", locale.supportFloatAria);
  setAttr("heroTopImage", "alt", locale.heroTopImageAlt);
  setText("heroTitle", locale.heroTitle);
  setText("heroTagline", locale.heroTagline);
  setText("githubBtnText", locale.githubBtnText);
  setAttr("githubBtn", "aria-label", locale.githubBtnAria);
  setText("releaseBtnText", locale.releaseBtnText);
  setAttr("releaseBtn", "aria-label", locale.releaseBtnAria);

  setText("aboutTitle", locale.aboutTitle);
  setHtml("aboutP1", locale.aboutP1);
  setText("aboutP2", locale.aboutP2);
  setText("aboutP3", locale.aboutP3);
  setText("introVideoCredit", locale.introVideoCredit);
  setText("introVideoReplay", locale.introVideoReplay);

  setText("howTitle", locale.howTitle);
  setAttr("flowDiagram", "aria-label", locale.flowDiagramAria);
  setText("flowNodeIyagi", locale.flowNodeIyagi);
  setText("flowNodeDosbox", locale.flowNodeDosbox);
  setText("flowNodeBridge", locale.flowNodeBridge);
  setText("flowNodeBbs", locale.flowNodeBbs);
  setText("flowCaption", locale.flowCaption);

  setText("featuresTitle", locale.featuresTitle);
  setText("feature1Title", locale.feature1Title);
  setText("feature1Body", locale.feature1Body);
  setText("feature2Title", locale.feature2Title);
  setText("feature2Body", locale.feature2Body);
  setText("feature3Title", locale.feature3Title);
  setHtml("feature3Body", locale.feature3Body);
  setText("feature4Title", locale.feature4Title);
  setText("feature4Body", locale.feature4Body);
  setText("feature5Title", locale.feature5Title);
  setText("feature5Body", locale.feature5Body);
  setText("feature6Title", locale.feature6Title);
  setText("feature6Body", locale.feature6Body);
  setText("feature7Title", locale.feature7Title);
  setText("feature7Body", locale.feature7Body);

  setText("screenshotsTitle", locale.screenshotsTitle);
  setText("screenshotsDesc", locale.screenshotsDesc);
  setAttr("screenshotMain", "alt", locale.screenshotMainAlt);
  setText("screenshotCaption", locale.screenshotCaption);
  setText("openScreenshots", locale.openScreenshots);

  setText("videoTitle", locale.videoTitle);
  setText("videoDesc", locale.videoDesc);
  setText("docsTitle", locale.docsTitle);
  setText("docsManualLink", locale.docsManualLink);

  setText("donationTitle", locale.donationTitle);
  setText("donationDesc", locale.donationDesc);
  setText("donationBtn", locale.donationBtn);
  setAttr("donationBtn", "aria-label", locale.donationBtnAria);

  setText("creditsTitle", locale.creditsTitle);
  setText("creditIyagiTeam", locale.creditIyagiTeam);
  setText("creditFontLink", locale.creditFontLink);

  setAttr("footerLogo", "alt", locale.footerLogoAlt);
  setText("licenseLinkText", locale.licenseLinkText);

  setAttr("screenshotsModal", "aria-label", locale.modalAria);
  setText("modalCloseBtn", locale.modalCloseBtn);
  setAttr("modalCloseBtn", "aria-label", locale.modalCloseAria);
  setText("modalTitle", locale.modalTitle);
  setAttr("modalImage1", "alt", locale.modalImage1Alt);
  setAttr("modalImage2", "alt", locale.modalImage2Alt);
}

function initLanguageSelector() {
  const buttons = document.querySelectorAll(".lang-btn");
  if (!buttons.length) {
    return;
  }

  const stored = localStorage.getItem("iyagi-doc-lang");
  const initialLang = I18N[stored] ? stored : "ko";
  applyLanguage(initialLang);

  buttons.forEach(function (btn) {
    if (btn.dataset.lang === initialLang) {
      btn.classList.add("is-active");
    } else {
      btn.classList.remove("is-active");
    }

    btn.addEventListener("click", function () {
      const nextLang = btn.dataset.lang;
      if (!I18N[nextLang]) {
        return;
      }
      localStorage.setItem("iyagi-doc-lang", nextLang);
      applyLanguage(nextLang);
      buttons.forEach(function (item) {
        item.classList.toggle("is-active", item.dataset.lang === nextLang);
      });
    });
  });
}

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
  initLanguageSelector();
  initScreenshotModal();
  initIntroMediaChain();
});
