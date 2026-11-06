import type { Metadata } from "next";
import type { ReactNode } from "react";
import { DocHeader, Toc } from "@/components/doc-header";
import { FaqList } from "@/components/faq-list";
import { Magnetic } from "@/components/magnetic";
import { faq } from "@/content/faq";
import { site } from "@/content/site";

const description =
  "Help with Headroom: first-run setup, folder access, stale readings, Copilot session activity and GitHub usage, widgets, sample data, and uninstalling.";

export const metadata: Metadata = {
  title: "Support",
  description,
  alternates: { canonical: "/support" },
  openGraph: { url: "/support", title: "Support · Headroom", description },
  twitter: { card: "summary_large_image", title: "Support · Headroom", description },
};

const fixes: { id: string; title: string; body: ReactNode }[] = [
  {
    id: "getting-started",
    title: "First launch: choose a tool or try sample data",
    body: (
      <>
        <p>
          Choose Claude, Codex or Copilot in the welcome window. Connect what you use, then choose{" "}
          <strong>Add another tool</strong> or <strong>Done</strong>. Every connection is optional.
          You can choose <strong>Set up later</strong> or <strong>Try sample data</strong> before
          granting access to anything.
        </p>
        <p>
          To return, open Headroom from Applications, then choose <strong>General</strong> &gt;{" "}
          <strong>Set up tools…</strong>. Existing connections stay in place. For Copilot,
          GitHub sign-in connects usage; <strong>Session activity</strong> connects desktop and CLI
          sessions separately. Start a new Copilot session after connecting it.
        </p>
      </>
    ),
  },
  {
    id: "pill-not-visible",
    title: "The pill is missing",
    body: (
      <>
        <p>
          Open Headroom from <strong>Applications</strong> in Finder. Opening it again brings up
          Settings. On macOS versions with <strong>System Settings &gt; Menu Bar &gt; Allow in the
          Menu Bar</strong>, make sure <strong>Headroom</strong> is on. If you use a menu bar
          manager, check its hidden items too.
        </p>
        <p>
          After changing displays, the menu bar may have less space. Close other menu bar items,
          then Command-drag Headroom toward the clock when it appears. You can also choose
          <strong> Always compact</strong> in Headroom&rsquo;s Settings.
        </p>
        <p>
          Headroom does not require Claude or Codex&rsquo;s own menu bar icons to be enabled.
          If toggling another app hides Headroom, or you see duplicate Headroom entries after
          using development builds, macOS may have kept an old permission association. Open the
          installed copy from Finder and <a href={`mailto:${site.email}`}>contact support</a>
          if it continues. Include your macOS version and a screenshot of the switches.
        </p>
      </>
    ),
  },
  {
    id: "grant-folders",
    title: "No rings, no sessions: grant folder access",
    body: (
      <>
        <p>
          Headroom can only read folders you allow. Click its pill in the menu bar, then{" "}
          <strong>Give access</strong>, or open <strong>Settings</strong> from the gear menu, choose{" "}
          <strong>Tools</strong> and click <strong>Grant access</strong> next to each folder. The
          folder picker opens in the right place, so you only confirm.
        </p>
        <ul>
          <li>
            <code>~/.claude</code> for Claude Code sessions and context.
          </li>
          <li>
            <code>~/Library/Application Support/Claude</code> for the plan limits the Claude desktop
            app records.
          </li>
          <li>
            <code>~/.codex</code> for Codex limits and sessions, if you track Codex. Read only.
          </li>
        </ul>
        <p>
          Headroom only asks for folders that exist. If Settings says Claude Code, the Claude desktop
          app or Codex isn&rsquo;t found, that folder isn&rsquo;t needed yet.
        </p>
      </>
    ),
  },
  {
    id: "as-of",
    title: "The rings say “as of”",
    body: (
      <>
        <p>
          &ldquo;As of 42m ago&rdquo; means the newest usage reading is more than 30 minutes old, so
          the rings are drawn faded. The limits come from the Claude desktop app, which records them
          about every 15 minutes while it&rsquo;s open, or from connected terminal sessions as they
          run. Open the Claude app, or keep working in a connected terminal session, and the rings
          catch up.
        </p>
        <p>
          Codex records its limits only while you use it, so its rows often say &ldquo;as of&rdquo;.
          While no Codex session is running on this Mac, nothing here can have changed them, so the
          ring isn&rsquo;t faded; it fades only when Codex is running and the number hasn&rsquo;t caught
          up. They catch up the next time you use Codex. A limit that has reset since then reads{" "}
          <code>0% reset since last reading</code>.
        </p>
        <p>
          A tilde before a reset time, as in <code>resets ~Sun 7 PM</code>, means Headroom worked it
          out from your usage history instead of reading an exact time.
        </p>
      </>
    ),
  },
  {
    id: "connect-terminal",
    title: "Terminal sessions or limits are missing: connect the terminal",
    body: (
      <>
        <p>
          Click the pill, then the gear, then <strong>Connect terminal</strong>, and confirm. Headroom
          backs up <code>~/.claude/settings.json</code> first, adds a status line and hooks, and
          keeps your own status line working. Sessions you start after connecting show up with their
          limits and status. Restart sessions that were already running.
        </p>
      </>
    ),
  },
  {
    id: "disconnect-terminal",
    title: "Disconnect the terminal",
    body: (
      <p>
        Gear menu, then <strong>Disconnect terminal</strong>. It removes exactly what Connect
        terminal added to <code>~/.claude/settings.json</code>, restores your original status line,
        and deletes <code>~/.claude/headroom</code>.
      </p>
    ),
  },
  {
    id: "connect-copilot-cli",
    title: "Copilot desktop and CLI: connect session activity",
    body: (
      <p>
        Open <strong>Settings</strong>, choose <strong>Tools</strong>, turn on{" "}
        <strong>Track Copilot</strong>. Under <strong>Session activity</strong>, click{" "}
        <strong>Connect sessions…</strong>, grant access to <code>~/.copilot</code> if asked, and
        confirm the changes. Headroom adds one hook file and a small script there. Start a new
        Copilot desktop or CLI session to load the connection; existing sessions do not pick it
        up immediately. If the row offers <strong>Update…</strong>, update it and start a new
        session. GitHub sign-in alone does not connect sessions or completion moments. To undo
        the connection, click <strong>Disconnect</strong> in the same row.
      </p>
    ),
  },
  {
    id: "connect-github",
    title: "Copilot usage: connect GitHub",
    body: (
      <>
        <p>
          In <strong>Settings</strong>, <strong>Tools</strong>, GitHub Copilot, click{" "}
          <strong>Connect GitHub</strong>. Headroom shows a code: click{" "}
          <strong>Copy Code and Open GitHub</strong>, paste it on GitHub and approve. If the
          <strong> Plan</strong> picker appears, choose the plan you pay for so Headroom can show a
          percent. When GitHub supplies an organization seat&rsquo;s allowance, no plan choice is needed.
        </p>
        <p>
          If an organization pays for your seat, Headroom shows that seat&rsquo;s monthly credits.
          &ldquo;No usage billed to you this month&rdquo; means GitHub has no Copilot usage on your
          own account this month and shared no organization seat. To stop,
          click <strong>Disconnect</strong>; to revoke the grant on GitHub too, go to{" "}
          <a href={site.githubAuthorizationsUrl}>github.com/settings/apps/authorizations</a>.
        </p>
      </>
    ),
  },
  {
    id: "widgets",
    title: "Add the widgets",
    body: (
      <p>
        Control-click the desktop, choose <strong>Edit Widgets</strong> and search for Headroom (or
        edit Notification Center the same way). <strong>Limits</strong> shows the rings,{" "}
        <strong>Sessions</strong> what&rsquo;s running. A widget that says{" "}
        <strong>Open Headroom</strong> or <strong>Headroom isn&rsquo;t running</strong> needs the app
        open: macOS refreshes widgets on its own schedule, so give it a few minutes. To hide session
        names in widgets, turn off <strong>Show session names in widgets</strong> in Settings.
      </p>
    ),
  },
  {
    id: "sample-data",
    title: "Sessions you don’t recognize: sample data",
    body: (
      <p>
        Choose <strong>Try sample data</strong> in setup, or <strong>Preview with sample data</strong>
        {" "}in an empty panel, to see made-up sessions and limits. The same switch
        is in Settings, as <strong>Show sample data</strong>. While it&rsquo;s on, the panel footer
        reads <strong>Sample data · Turn off</strong>. Click <strong>Turn off</strong> to go back to
        your own data.
      </p>
    ),
  },
  {
    id: "moments",
    title: "Turn off moments",
    body: (
      <p>
        Don&rsquo;t want the pill to widen when a session finishes or needs you? Open{" "}
        <strong>Settings</strong> from the gear menu and turn off <strong>Show moments</strong>. To
        stop &ldquo;needs you&rdquo; from staying in the menu bar until you look, turn off{" "}
        <strong>Keep &ldquo;needs you&rdquo; in the menu bar until I look</strong>. When you answer
        directly in Codex and the task resumes, the notice clears on Headroom&rsquo;s next refresh,
        normally within two seconds after Codex writes the updated session event.
        If the tool still reports an old request, hover the session in the panel and click{" "}
        <strong>Dismiss</strong>.
      </p>
    ),
  },
  {
    id: "menu-bar-space",
    title: "A crowded menu bar",
    body: (
      <>
        <p>
          Open <strong>Settings</strong> &gt; <strong>General</strong> &gt; <strong>Menu bar</strong>{" "}
          and choose a <strong>Display</strong> setting. <strong>Automatic</strong> expands task
          titles when space allows and keeps every gauge you selected. <strong>Always compact</strong>{" "}
          keeps one gauge; click the pill to read full titles in the panel.
        </p>
        <p>
          macOS decides which menu bar items fit. Hold Command and drag Headroom toward the clock
          to give it a better position when space is tight.
        </p>
      </>
    ),
  },
  {
    id: "warning-percentages",
    title: "Percentages beside the rings",
    body: (
      <p>
        A tool&rsquo;s percentage appears when its highest usage reaches 75%, when its ring turns
        orange. At 95%, it turns red. With <strong>One gauge per tool</strong> enabled, each Claude,
        Codex and Copilot gauge shows its own warning percentage, even if another tool is closer to
        its limit. Below 75%, the rings stay visible without a number. <strong>Always compact</strong>{" "}
        keeps the single gauge chosen under <strong>Rings show</strong>.
      </p>
    ),
  },
  {
    id: "codex-after-relaunch",
    title: "Codex tasks already running when Headroom opens",
    body: (
      <p>
        Headroom recovers their status from local session history, so you don&rsquo;t need to
        restart your Codex tasks. Very long histories can take more than one refresh to catch up.
        If a task is still missing, check that <strong>Track Codex</strong> is on and its folder
        access is granted in <strong>Settings</strong> &gt; <strong>Tools</strong>.
      </p>
    ),
  },
  {
    id: "quit-uninstall",
    title: "Quit or uninstall",
    body: (
      <>
        <p>
          To quit, click the pill, then the gear, then <strong>Quit Headroom</strong>. To stop it
          from opening when you log in, turn off <strong>Launch at login</strong> in Settings.
        </p>
        <p>To uninstall:</p>
        <ol className="mt-3 list-decimal space-y-2 pl-6 marker:text-subtle">
          <li>
            If you connected the terminal or Copilot sessions, choose <strong>Disconnect terminal</strong>{" "}
            and <strong>Disconnect</strong> under Copilot&rsquo;s Session activity first. That removes the status line and hooks
            (the bridge) from <code>~/.claude/settings.json</code> and deletes{" "}
            <code>~/.claude/headroom</code>, and removes <code>~/.copilot/hooks/headroom.json</code>{" "}
            and <code>~/.copilot/headroom</code>.
          </li>
          <li>
            If you connected GitHub, choose <strong>Disconnect</strong> in Settings, Tools, GitHub
            Copilot. To revoke the grant on GitHub too, go to{" "}
            <a href={site.githubAuthorizationsUrl}>github.com/settings/apps/authorizations</a>.
          </li>
          <li>Quit Headroom.</li>
          <li>Move Headroom from your Applications folder to the Trash.</li>
          <li>
            To remove its settings and the widgets&rsquo; summary too, delete{" "}
            <code>{site.containerPath}</code> and <code>{site.groupContainerPath}</code> if
            they&rsquo;re still there. In the Finder, choose Go › Go to Folder and paste each path.
          </li>
        </ol>
        <p className="mt-4">
          Already deleted it without disconnecting? The status line and hooks stay in{" "}
          <code>~/.claude/settings.json</code>, and the bridge keeps writing its status files until
          both the app and its container (step 5) are gone. After that it writes nothing and only runs
          the status line you had before, if any. To remove the entries, install Headroom again and
          choose Disconnect terminal. Copilot&rsquo;s hook works the same way: it stops writing
          once Headroom and its container are gone, and Disconnect under Session activity, or deleting{" "}
          <code>~/.copilot/hooks/headroom.json</code> and <code>~/.copilot/headroom</code>, removes it.
        </p>
      </>
    ),
  },
];

const toc = [
  { id: "contact", label: "Contact" },
  { id: "quick-fixes", label: "Quick fixes" },
  ...fixes.map((fix) => ({ id: fix.id, label: fix.title.split(":")[0] })),
  { id: "faq", label: "FAQ" },
];

export default function SupportPage() {
  return (
    <div className="wrap">
      <DocHeader eyebrow="Support" title="Help with Headroom.">
        <p>
          Get Headroom free from the <a className="text-link" href={site.appStoreUrl}>Mac App Store</a>. Requires {site.minimumSystem}.
        </p>
        <p>
          Most questions have a quick answer below. If yours doesn&rsquo;t, write to{" "}
          <a className="text-link" href={`mailto:${site.email}`}>
            {site.email}
          </a>{" "}
          and you&rsquo;ll hear back from the person who makes Headroom.
        </p>
      </DocHeader>

      <div className="grid gap-12 border-t border-line pb-24 pt-4 sm:pb-32 lg:grid-cols-[220px_minmax(0,760px)] lg:gap-20">
        <Toc items={toc} />
        <div>
          <section
            id="contact"
            aria-labelledby="contact-title"
            className="glass-card mt-10 flex flex-col gap-6 p-6 sm:flex-row sm:items-center sm:justify-between sm:p-8"
          >
            <div>
              <h2 id="contact-title" className="text-[22px] font-medium tracking-[-0.025em]">
                Email support
              </h2>
              <p className="mt-2 max-w-[46ch] text-[15px] leading-relaxed text-muted">
                Include your macOS version, and which tools you use Headroom with: the Claude app,
                Claude Code in a terminal, Codex or Copilot. Screenshots show session names, so crop
                what you&rsquo;d rather keep private.
              </p>
            </div>
            <Magnetic className="shrink-0">
              <a
                href={`mailto:${site.email}?subject=Headroom%20support`}
                className="inline-flex min-h-12 items-center gap-2 rounded-full bg-teal px-5 text-[15px] font-semibold text-ink transition-colors hover:bg-[#7fd9ba]"
              >
                {site.email}
              </a>
            </Magnetic>
          </section>

          <article className="doc">
            <h2 id="quick-fixes">Quick fixes</h2>
            <p>Headroom needs {site.minimumSystem}. None of these involve a Headroom account.</p>
            {fixes.map((fix) => (
              <section key={fix.id} aria-labelledby={fix.id}>
                <h3 id={fix.id}>
                  {fix.title}
                </h3>
                {fix.body}
              </section>
            ))}
          </article>

          <section aria-labelledby="faq" className="mt-16">
            <h2 id="faq" className="mb-6 text-[clamp(24px,2.4vw,30px)] font-medium tracking-[-0.03em]">
              FAQ
            </h2>
            <FaqList items={faq} />
          </section>
        </div>
      </div>
    </div>
  );
}
