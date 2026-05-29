import { serve } from "bun";
import { createHmac, timingSafeEqual } from "node:crypto";

const PORT = Number(process.env.PORT) || 8080;
const SECRET = process.env.WEBHOOK_SECRET;
const ALLOWED_REPOS = csv(process.env.ALLOWED_REPOS);
const ALLOWED_ASSOCIATIONS = new Set(
  csv(process.env.ALLOWED_ASSOCIATIONS, "OWNER,MEMBER,COLLABORATOR"),
);
// The controller no longer runs run-michel.sh itself — it dispatches each
// accepted mention to a worker sprite (one run per worker, real parallelism).
const DISPATCH_SCRIPT = process.env.DISPATCH_SCRIPT || "/home/sprite/workspace/scripts/dispatch-michel.sh";
const WORKDIR = process.env.WORKDIR || "/home/sprite/workspace";
const MICHEL_RE = /(^|\W)@michel(\W|$)/i;

if (!SECRET) {
  console.error("FATAL: WEBHOOK_SECRET env var is required");
  process.exit(1);
}
if (ALLOWED_REPOS.length === 0) {
  console.error("FATAL: ALLOWED_REPOS env var is required (csv of owner/repo)");
  process.exit(1);
}

function csv(v: string | undefined, fallback = ""): string[] {
  return (v ?? fallback)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function verifySignature(rawBody: string, header: string | null): boolean {
  if (!header || !header.startsWith("sha256=")) return false;
  const provided = Buffer.from(header.slice("sha256=".length), "hex");
  const expected = createHmac("sha256", SECRET!).update(rawBody).digest();
  if (provided.length !== expected.length) return false;
  return timingSafeEqual(provided, expected);
}

function log(level: "info" | "warn", event: string, fields: Record<string, unknown>) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level, event, ...fields }));
}

const server = serve({
  port: PORT,
  routes: {
    "/healthz": () => new Response("ok\n", { status: 200 }),

    "/github-webhook": {
      async POST(req) {
        const rawBody = await req.text();
        const sig = req.headers.get("x-hub-signature-256");
        if (!verifySignature(rawBody, sig)) {
          log("warn", "rejected", { reason: "bad_signature" });
          return new Response("bad signature\n", { status: 401 });
        }

        const ghEvent = req.headers.get("x-github-event");
        if (ghEvent !== "issue_comment") {
          log("info", "ignored", { reason: "wrong_event", gh_event: ghEvent });
          return new Response("ignored\n", { status: 204 });
        }

        let payload: any;
        try {
          payload = JSON.parse(rawBody);
        } catch {
          log("warn", "rejected", { reason: "bad_json" });
          return new Response("bad json\n", { status: 400 });
        }

        if (payload.action !== "created") {
          log("info", "ignored", { reason: "wrong_action", action: payload.action });
          return new Response("ignored\n", { status: 204 });
        }

        const repo: string = payload.repository?.full_name ?? "";
        const issue: number = payload.issue?.number;
        const body: string = payload.comment?.body ?? "";
        const author: string = payload.comment?.user?.login ?? "";
        const association: string = payload.comment?.author_association ?? "";

        if (!MICHEL_RE.test(body)) {
          log("info", "ignored", { reason: "no_mention", repo, issue, author });
          return new Response("no mention\n", { status: 204 });
        }

        if (!ALLOWED_REPOS.includes(repo)) {
          log("warn", "rejected", { reason: "repo_not_allowed", repo, issue, author });
          return new Response("repo not allowed\n", { status: 403 });
        }

        if (!ALLOWED_ASSOCIATIONS.has(association)) {
          log("warn", "rejected", { reason: "author_not_allowed", repo, issue, author, association });
          return new Response("author not allowed\n", { status: 403 });
        }

        log("info", "accepted", { repo, issue, author, association });

        Bun.spawn([DISPATCH_SCRIPT, repo, String(issue)], {
          cwd: WORKDIR,
          stdout: "inherit",
          stderr: "inherit",
        });

        return Response.json({ ok: true, repo, issue }, { status: 202 });
      },
    },
  },

  fetch() {
    return new Response("Not Found\n", { status: 404 });
  },
});

console.log(`michel-webhook listening on ${server.url}`);
console.log(`allowed_repos=${JSON.stringify(ALLOWED_REPOS)} allowed_associations=${JSON.stringify([...ALLOWED_ASSOCIATIONS])}`);
