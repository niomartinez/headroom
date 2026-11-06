export type FaqItem = { question: string; answer: string[] };

/** Shown on the home page and on /support. Plain words, sentence case. */
export const faq: FaqItem[] = [
  {
    question: "Where do I get Headroom?",
    answer: ["Download Headroom free from the Mac App Store using the download button on the Headroom home page. It runs on macOS 14 Sonoma or later."],
  },
  {
    question: "Is Headroom made by Anthropic, OpenAI or GitHub?",
    answer: [
      "No. Headroom is an independent app made by Nio Martinez. It isn't made by, affiliated with or endorsed by Anthropic, OpenAI or GitHub.",
    ],
  },
  {
    question: "Does it need my Claude login?",
    answer: [
      "No. There is no Headroom account, and it never asks for your Claude login. Headroom reads files that Claude Code and the Claude desktop app already write on your Mac.",
    ],
  },
  {
    question: "Does Headroom read my Codex login?",
    answer: ["No. It reads Codex's session files and never opens its sign-in file."],
  },
  {
    question: "Why does Copilot need a sign-in?",
    answer: [
      "Copilot's usage is kept on GitHub, not on your Mac. Headroom uses its own read-only GitHub sign-in, only if you turn it on.",
    ],
  },
  {
    question: "Can I see my company's Copilot seat?",
    answer: [
      "Yes. If an organization pays for your Business or Enterprise seat, nothing is billed to you, so Headroom asks GitHub for that seat's monthly AI credits instead, with the same read-only sign-in, and shows them as a percent.",
    ],
  },
  {
    question: "Does it send my data anywhere?",
    answer: [
      "No. Headroom has no analytics, collects nothing and sends nothing to its developer. Claude and Codex work entirely from files on your Mac.",
      "The one exception is opt-in: if you connect GitHub, Headroom asks GitHub for this month's Copilot usage, and talks to nothing else.",
    ],
  },
  {
    question: "Which plans does it work with?",
    answer: [
      "Claude: the 5-hour and weekly limits show for Pro and Max plans, and they cover chat, Cowork and Claude Code alike. Sessions and context bars show for anyone using Claude Code. If you use Claude Code in the terminal, click Connect terminal once, so Headroom can see those sessions and their limits too.",
      "Codex: the weekly limit, as Codex records it while you use it. With an API key there are no limits to show.",
      "Copilot: this month's usage. On a plan you pay for yourself, pick it in Settings to see a percent; a Business or Enterprise seat shows its monthly credits as a percent on its own.",
    ],
  },
  {
    question: "How do I add the widgets?",
    answer: [
      "Control-click the desktop and choose Edit Widgets, then search for Headroom. Limits shows the rings; Sessions shows what's running. Both come in Notification Center too.",
    ],
  },
  {
    question: "Which Macs does it run on?",
    answer: ["Any Mac with macOS 14 Sonoma or later."],
  },
  {
    question: "Is it free?",
    answer: ["Yes. Headroom is free, with no ads and no account."],
  },
];
