import assert from "node:assert/strict";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(
    new Request("http://localhost/", { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the Context Lens product demo", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  const html = await response.text();
  assert.match(html, /<title>Context · 英语上下文学习助手<\/title>/i);
  assert.match(html, /今日复习/);
  assert.match(html, /我的词库/);
  assert.match(html, /阅读收藏/);
  assert.match(html, /今天继续一点点/);
  assert.doesNotMatch(html, /Yiming|vinext-starter|Your site is taking shape/);
});

test("exposes the core learning loop in the initial UI", async () => {
  const html = await (await render()).text();
  assert.match(html, /从语境中，重新想起它/);
  assert.match(html, /点击查看语境释义/);
  assert.match(html, /忘记了/);
  assert.match(html, /有点模糊/);
  assert.match(html, /记得很清楚/);
});
