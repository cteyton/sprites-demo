import { serve } from "bun";
import index from "./index.html";
import { queries, type Severity, type Status, type Task } from "./db";

const VALID_STATUS: Status[] = ["todo", "in_progress", "done"];
const VALID_SEVERITY: Severity[] = ["high", "medium", "low"];
const MAX_DESC = 500;
const MAX_NAME = 200;

function bad(message: string, status = 400) {
  return Response.json({ error: message }, { status });
}

function sanitizeInput(body: unknown): { name?: string; description?: string; status?: Status; severity?: Severity; position?: number } | null {
  if (!body || typeof body !== "object") return null;
  return body as any;
}

const server = serve({
  port: Number(process.env.PORT) || 3000,
  development: process.env.NODE_ENV !== "production",
  routes: {
    "/": index,

    "/api/tasks": {
      async GET() {
        return Response.json(queries.list.all());
      },
      async POST(req) {
        const body = sanitizeInput(await req.json().catch(() => null));
        if (!body) return bad("invalid json");

        const name = typeof body.name === "string" ? body.name.trim() : "";
        const description = typeof body.description === "string" ? body.description : "";

        if (!name) return bad("name required");
        if (name.length > MAX_NAME) return bad(`name max ${MAX_NAME} chars`);
        if (description.length > MAX_DESC) return bad(`description max ${MAX_DESC} chars`);

        const { max } = queries.maxPosition.get({ $status: "todo" }) ?? { max: -1 };
        const position = (max ?? -1) + 1;

        const task = queries.insert.get({ $name: name, $description: description, $position: position });
        return Response.json(task, { status: 201 });
      },
    },

    "/api/tasks/:id": {
      async PATCH(req) {
        const id = Number(req.params.id);
        if (!Number.isInteger(id)) return bad("invalid id");
        const current = queries.get.get({ $id: id });
        if (!current) return bad("not found", 404);

        const body = sanitizeInput(await req.json().catch(() => null));
        if (!body) return bad("invalid json");

        const name = (body.name ?? current.name).toString().trim();
        const description = (body.description ?? current.description).toString();
        const status = (body.status ?? current.status) as Status;
        const severity = (body.severity ?? current.severity) as Severity;
        const position = typeof body.position === "number" ? body.position : current.position;

        if (!name) return bad("name required");
        if (name.length > MAX_NAME) return bad(`name max ${MAX_NAME} chars`);
        if (description.length > MAX_DESC) return bad(`description max ${MAX_DESC} chars`);
        if (!VALID_STATUS.includes(status)) return bad("invalid status");
        if (!VALID_SEVERITY.includes(severity)) return bad("invalid severity");

        const updated = queries.update.get({
          $id: id,
          $name: name,
          $description: description,
          $status: status,
          $severity: severity,
          $position: position,
        });
        return Response.json(updated);
      },
      async DELETE(req) {
        const id = Number(req.params.id);
        if (!Number.isInteger(id)) return bad("invalid id");
        queries.remove.run({ $id: id });
        return new Response(null, { status: 204 });
      },
    },
  },

  fetch() {
    return new Response("Not Found", { status: 404 });
  },
});

console.log(`Server running at ${server.url}`);
