import type { Metadata } from "next";
import Link from "next/link";
import { DocHeader, Toc } from "@/components/doc-header";
import { site } from "@/content/site";

const description =
  "Headroom collects no data and has no analytics. What the app reads on your Mac, what it writes, when it talks to GitHub (only if you connect it), and what this website logs.";

export const metadata: Metadata = {
  title: "Privacy policy",
  description,
  alternates: { canonical: "/privacy" },
  openGraph: { url: "/privacy", title: "Privacy policy · Headroom", description },
  twitter: { card: "summary_large_image", title: "Privacy policy · Headroom", description },
};

const sections = [
  { id: "short-version", label: "The short version" },
  { id: "what-it-reads", label: "What the app reads" },
  { id: "what-it-stores", label: "What the app stores" },
  { id: "connect-terminal", label: "Connect terminal" },
  { id: "connect-copilot-cli", label: "Connect Copilot sessions" },
  { id: "github", label: "Copilot usage and GitHub" },
  { id: "network", label: "Network and third parties" },
  { id: "website", label: "This website" },
  { id: "changes", label: "Children and changes" },
  { id: "contact", label: "Contact" },
];

export default function PrivacyPage() {
  return (
    <div className="wrap">
      <DocHeader eyebrow="Privacy policy" title="Your data stays on your Mac.">
        <p>
          Headroom collects nothing. This policy explains what the app reads, what it writes, when
          it talks to GitHub, and what this website logs.
        </p>
        <p className="mt-4 text-[15px] text-subtle">Effective {site.privacyEffectiveDate}</p>
      </DocHeader>

      <div className="grid gap-12 border-t border-line pb-24 pt-4 sm:pb-32 lg:grid-cols-[220px_minmax(0,760px)] lg:gap-20">
        <Toc items={sections} />
        <article className="doc">
          <h2 id="short-version">The short version</h2>
          <ul>
            <li>
              <strong>Headroom collects no data.</strong> No analytics, no tracking and no Headroom
              account.
            </li>
            <li>
              <strong>Local by default.</strong> Everything about Claude and Codex comes from files
              those tools already write on your Mac, and the app makes no network requests for them.
            </li>
            <li>
              <strong>GitHub only if you connect it.</strong> To show GitHub Copilot&rsquo;s usage,
              which is kept on GitHub, Headroom talks to GitHub, and only to GitHub, after you connect
              your account.
            </li>
            <li>
              <strong>Nothing reaches us.</strong> There is nothing for us to see, share or sell.
            </li>
          </ul>

          <h2 id="what-it-reads">What the app reads</h2>
          <p>
            The Mac App Store version of Headroom runs in Apple&rsquo;s app sandbox, so it can only
            read folders you choose. It asks for each one once, in a standard macOS folder picker, and
            only for folders that exist on your Mac:
          </p>
          <ul>
            <li>
              <code>~/.claude</code>, Claude Code&rsquo;s folder. Headroom reads the session files in{" "}
              <code>~/.claude/sessions</code> to see which sessions are running, their names,
              project folders and status. From the end of each session&rsquo;s transcript in{" "}
              <code>~/.claude/projects</code> it reads the token counts and model name, to show
              how full the context is. It doesn&rsquo;t keep or show the text of your
              conversations. It asks for read and write access to this folder only for the
              optional Connect terminal feature, below.
            </li>
            <li>
              <code>~/Library/Application Support/Claude</code>, read only. Headroom reads{" "}
              <code>plan-usage-history.json</code>, where the Claude desktop app records your 5-hour
              and weekly plan usage. While a Claude app session is under Just finished, it also reads
              the start of that app&rsquo;s session files in <code>claude-code-sessions</code> for one
              field, <code>lastFocusedAt</code>, to see when you last opened each session there.
            </li>
            <li>
              <code>~/.codex</code>, OpenAI Codex&rsquo;s folder, read only and only if you track
              Codex. Headroom reads Codex&rsquo;s session files in <code>~/.codex/sessions</code> for
              your Codex limits, which threads are running and how full their context is, plus the
              thread titles Codex keeps. It uses only the fields it needs and never keeps or shows your
              prompts or Codex&rsquo;s replies. While a Codex app thread is under Just finished, it
              reads the list of unread thread ids in <code>.codex-global-state.json</code>, and nothing
              else from that file. It never opens <code>auth.json</code> (your Codex sign-in) or
              Codex&rsquo;s configuration.
            </li>
            <li>
              <code>~/.copilot</code>, only if you choose Connect sessions, below. There Headroom
              reads only the small records its own hook writes, and the names (not the contents) of
              Copilot&rsquo;s log files, to tell which sessions are still running.
            </li>
          </ul>
          <p>
            Headroom reads these files on your Mac while it runs, to draw the pill, the panel and the
            widgets. It doesn&rsquo;t copy them anywhere and keeps no history of them.
          </p>

          <h2 id="what-it-stores">What the app stores</h2>
          <ul>
            <li>
              Its own settings, such as launch at login and whether moments show, and the folder
              permissions you granted. macOS keeps them in the app&rsquo;s own container,{" "}
              <code>{site.containerPath}</code>.
            </li>
            <li>
              A small summary for the widgets: your limits, and your sessions without their process
              ids or folder paths (and without their names, if you turn names off in Settings). It
              lives in the app&rsquo;s shared container,{" "}
              <code>{site.groupContainerPath}</code>, which only Headroom and its widgets can read.
            </li>
            <li>
              If you connect GitHub, your GitHub sign-in (an access token and a refresh token) in
              Headroom&rsquo;s own item in your Mac&rsquo;s keychain, and your GitHub username in its
              settings.
            </li>
          </ul>
          <p>
            Deleting the app can leave those folders behind; if they&rsquo;re still there, you can
            delete them too. <Link href="/support#quit-uninstall">Support</Link> explains how.
          </p>

          <h2 id="connect-terminal">Connect terminal (optional)</h2>
          <p>
            Claude Code in the terminal doesn&rsquo;t write its plan limits to a file on its own.
            If you click <strong>Connect terminal</strong> and confirm the dialog that lists every
            change, Headroom:
          </p>
          <ul>
            <li>
              backs up <code>~/.claude/settings.json</code> to{" "}
              <code>~/.claude/settings.json.headroom-backup</code> first;
            </li>
            <li>
              adds a status line and hooks to <code>~/.claude/settings.json</code>, keeping your own
              status line working and every other setting as it was;
            </li>
            <li>
              writes a small script, <code>~/.claude/headroom/bridge.sh</code>, that Claude Code
              runs.
            </li>
          </ul>
          <p>
            The script writes small status files to <code>~/.claude/headroom</code> on your Mac,
            for Headroom to read: session ids, folder paths, event names, and context and limit
            numbers. It never saves your prompts. <strong>Disconnect terminal</strong> removes
            exactly what was added, restores your original status line and deletes{" "}
            <code>~/.claude/headroom</code>.
          </p>
          <p>
            Disconnect before you delete Headroom. If you don&rsquo;t, the script keeps writing
            those files until both the app and its container are gone.{" "}
            <Link href="/support#quit-uninstall">Support</Link> explains how to clean up.
          </p>

          <h2 id="connect-copilot-cli">Connect Copilot sessions (optional)</h2>
          <p>
            To show GitHub Copilot desktop or CLI sessions, click <strong>Connect sessions…</strong> under
            <strong> Session activity</strong> and
            grant access to <code>~/.copilot</code> if asked. Confirm the dialog that lists every change.
            Headroom adds two things, leaving your own Copilot settings alone:
          </p>
          <ul>
            <li>
              <code>~/.copilot/hooks/headroom.json</code>, its own hook file, which Copilot reads
              when a session starts;
            </li>
            <li>
              a small script in <code>~/.copilot/headroom</code>, which those hooks run.
            </li>
          </ul>
          <p>
            The script writes one small record per session to{" "}
            <code>~/.copilot/headroom/sessions</code>: the session id, its folder path, the event
            name and notification type, and process ids. It never saves your prompts. Headroom never
            opens Copilot&rsquo;s own <code>config.json</code>, settings or session history.{" "}
            <strong>Disconnect</strong> under Session activity removes both again. New sessions load the
            connection; GitHub sign-in for usage is separate.
          </p>

          <h2 id="github">Copilot usage and GitHub (optional)</h2>
          <p>
            GitHub Copilot&rsquo;s usage is kept on GitHub, not on your Mac. If you click{" "}
            <strong>Connect GitHub</strong>, you sign in on github.com with GitHub&rsquo;s device
            code, and grant Headroom&rsquo;s own GitHub app read-only access to your plan&rsquo;s
            billing. Headroom never uses the sign-in of the GitHub CLI, VS Code or Copilot.
          </p>
          <ul>
            <li>
              Headroom then connects to <code>github.com</code> (to sign in and renew the sign-in) and{" "}
              <code>api.github.com</code>, about every 15 minutes, and to nothing else.
            </li>
            <li>
              It sends your sign-in token and the current year and month. It receives your GitHub
              username and this month&rsquo;s Copilot usage: on a seat an organization pays for,
              that seat&rsquo;s plan and monthly credits.
            </li>
            <li>Nothing goes to the developer or anyone else. GitHub&rsquo;s own privacy terms apply to your GitHub account.</li>
            <li>
              <strong>Disconnect</strong> deletes the token from your Mac. To revoke the grant on
              GitHub too, go to{" "}
              <a href={site.githubAuthorizationsUrl}>github.com/settings/apps/authorizations</a>.
            </li>
          </ul>

          <h2 id="network">Network and third parties</h2>
          <p>
            Apart from GitHub, if you connect it, the app doesn&rsquo;t connect to the internet. It
            contains no analytics, advertising or crash reporting code from anyone. If you share
            analytics with app developers in macOS (System Settings, Privacy &amp; Security,
            Analytics &amp; Improvements), Apple may pass on anonymous crash reports. Apple controls
            that, and you can turn it off there.
          </p>

          <h2 id="website">This website</h2>
          <p>
            headroom.niomartinez.com is a static website hosted on Vercel. It sets no cookies and
            uses no analytics or tracking scripts. Like any web host, Vercel may log standard request
            data, such as your IP address, browser, the page you asked for and the time, to deliver
            the site and keep it secure. See{" "}
            <a href="https://vercel.com/legal/privacy-policy">Vercel&rsquo;s privacy policy</a>.
          </p>
          <p>
            If you email us, we use your message and address only to reply, and don&rsquo;t share
            them.
          </p>

          <h2 id="changes">Children and changes</h2>
          <p>
            Headroom isn&rsquo;t directed at children, and it collects no data from anyone. If this
            policy changes, the new version will be posted on this page with a new effective date.
          </p>

          <h2 id="contact">Contact</h2>
          <p>
            Headroom is made by {site.owner}. Questions about privacy go to{" "}
            <a href={`mailto:${site.email}`}>{site.email}</a>.
          </p>
        </article>
      </div>
    </div>
  );
}
