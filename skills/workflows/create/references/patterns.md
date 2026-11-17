# Workflow patterns

Code shapes for the rules in the main skill. Each `sdk.runAction` call keeps its `appKey`, `actionType` and `actionKey` inline so the editor renders the step as an app action. App keys, action keys and connection aliases are for shape only: discover your own.

### Authenticated `sdk.fetch`

```typescript
const gitlabUser = await ctx.step("fetch-gitlab-user", async () => {
  const response = await sdk.fetch("https://gitlab.com/api/v4/user", {
    connection: "gitlab_work",
    method: "GET",
  });
  if (!response.ok) {
    throw new Error(`GitLab returned ${response.status}`);
  }
  return response.json();
});
```

### Filter pattern

Use an early return to filter out runs that don't meet a condition, and keep the side-effect-free condition logic outside `ctx.step` — filters add no value to the step graph. For complex multi-condition filters, use named const bindings:

```typescript
const tags = input.tags ?? [];
const isActiveAndUrgent = input.status === "active" && tags.includes("urgent");
const isHighPriority = (input.priority ?? 0) > 8;
const shouldRun = isActiveAndUrgent || isHighPriority;

if (!shouldRun) {
  return { skipped: true, reason: "filter-did-not-match" };
}
```

### Durable patterns

Keep waits at workflow scope, not inside a step:

```typescript
await ctx.wait("wait-before-followup", 3600);
```

Journal replay-variant values once:

```typescript
const createdAt = await ctx.step("capture-created-at", async () =>
  new Date().toISOString(),
);
```

Use callbacks for human approval:

```typescript
const [approvalPromise, callbackUrl] = await ctx.createCallback({
  name: "wait-for-approval",
  payloadSchema: z.object({ approved: z.boolean() }),
  timeoutSeconds: 86400,
});

await ctx.step("send-approval-request", async () =>
  sdk.runAction({
    appKey: "ExampleCLIAPI",
    actionType: "write",
    actionKey: "send_message",
    connection: "example_connection",
    inputs: { callbackUrl },
  }),
);

// With timeoutSeconds: { status: "delivered", value, at } | { status: "expired", at }
const approval = await approvalPromise;
if (approval.status === "expired") return { skipped: true, reason: "approval-timed-out" };
if (!approval.value.approved) return { skipped: true, reason: "denied" };
```

Use `Promise.all` outside steps for independent work, with one step per item:

```typescript
const results = await Promise.all(
  items.map((item, index) =>
    ctx.step(`process-item-${index}`, async () =>
      sdk.runAction({
        appKey: "ExampleCLIAPI",
        actionType: "write",
        actionKey: "do_something",
        connection: "example_connection",
        inputs: { item },
      }),
    ),
  ),
);
```

Use step retries for flaky external calls:

```typescript
const result = await ctx.step({
  name: "call-flaky-service",
  maxAttempts: 3,
  retryDelaySeconds: 5,
  run: async () =>
    sdk.runAction({
      appKey: "ExampleCLIAPI",
      actionType: "write",
      actionKey: "do_something",
      connection: "example_connection",
      inputs: {},
    }),
});
```
