import { chromium, expect } from "@playwright/test";
import { writeFile } from "node:fs/promises";
const browser = await chromium.launch({
  channel: process.env.BROWSER_CHANNEL || "chrome",
  headless: true,
});
const baseURL = process.env.PREVIEW_URL || "http://127.0.0.1:5190/";
const results = [];
const errors = [];
const page = await browser.newPage({
  viewport: { width: 1440, height: 960 },
  deviceScaleFactor: 1,
});
page.on("pageerror", (error) => errors.push(error.message));
page.on("console", (message) => {
  if (message.type() === "error") errors.push(message.text());
});
const check = async (name, fn) => {
  await fn();
  results.push({ name, passed: true });
  console.log(`PASS ${name}`);
};
try {
  await page.goto(baseURL, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await check("Desktop composition and responsive controls", async () => {
    await expect(
      page.getByRole("heading", { name: "A small change to my order" }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Open navigation", exact: true }),
    ).not.toBeVisible();
    await expect(
      page.getByRole("button", { name: "Back to inbox", exact: true }),
    ).not.toBeVisible();
    await expect(
      page.getByRole("complementary", { name: "Customer details" }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({ path: "evidence/desktop.png" });
  });
  await check("Search, selection and draft retention", async () => {
    const search = page.getByRole("textbox", { name: "Search conversations" });
    await search.fill("James");
    await expect(page.locator(".conversation-row")).toHaveCount(1);
    await page
      .getByRole("button", { name: "James Wilson: Where is my package?" })
      .click();
    await expect(
      page.getByRole("heading", { name: "Where is my package?" }),
    ).toBeVisible();
    await page
      .getByRole("textbox", { name: "Write a reply", exact: true })
      .fill("Checking the tracking for you.");
    await search.fill("");
    await page
      .getByRole("button", { name: "Sophie Chen: A small change to my order" })
      .click();
    await expect(
      page.getByRole("textbox", { name: "Write a reply", exact: true }),
    ).toHaveValue("");
    await page
      .getByRole("button", { name: "James Wilson: Where is my package?" })
      .click();
    await expect(
      page.getByRole("textbox", { name: "Write a reply", exact: true }),
    ).toHaveValue("Checking the tracking for you.");
    await page
      .getByRole("button", { name: "Sophie Chen: A small change to my order" })
      .click();
  });
  await check("Real filter dropdown and empty state", async () => {
    await page.getByRole("button", { name: "Filter conversations" }).click();
    await page.getByRole("menuitemcheckbox", { name: "Unread only" }).click();
    await expect(page.locator(".conversation-row")).toHaveCount(1);
    await page
      .getByRole("textbox", { name: "Search conversations" })
      .fill("nothing matches");
    await expect(page.getByText("No conversations here")).toBeVisible();
    await page.getByRole("button", { name: "Reset filters" }).click();
    await expect(page.locator(".conversation-row")).toHaveCount(8);
  });
  await check("Copilot draft, local reply and private note", async () => {
    await page.getByRole("tab", { name: "Copilot" }).click();
    await expect(page.getByText("A second pair of eyes.")).toBeVisible();
    await page.getByRole("button", { name: "Use example draft" }).click();
    const reply = page.getByRole("textbox", {
      name: "Write a reply",
      exact: true,
    });
    await expect(reply).toHaveValue(/Hi Sophie/);
    await page.getByRole("button", { name: "Send reply", exact: true }).click();
    await expect(page.getByRole("log")).toContainText(
      "I’ll update the shipping address",
    );
    await expect(reply).toHaveValue("");
    await page.getByRole("tab", { name: "Private note", exact: true }).click();
    await page
      .getByRole("textbox", { name: "Write a private note" })
      .fill("Confirm address before dispatch.");
    await page.getByRole("button", { name: "Add note", exact: true }).click();
    await expect(page.locator(".message.note")).toContainText(
      "Confirm address before dispatch.",
    );
    await page.getByRole("tab", { name: "Reply", exact: true }).click();
  });
  await check("Address review dialog, focus and local update", async () => {
    await page
      .getByRole("button", { name: "Edit shipping address", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(page.getByRole("dialog")).toContainText("24 Maple Street");
    await page.screenshot({ path: "evidence/address-review.png" });
    await page.getByRole("button", { name: "Confirm address" }).click();
    await expect(page.getByRole("dialog")).not.toBeVisible();
    await expect(page.getByText("Updated in preview")).toBeVisible();
    await page.getByRole("button", { name: "AI draft", exact: true }).click();
    await expect(
      page.getByRole("textbox", { name: "Write a reply", exact: true }),
    ).toHaveValue(/I’ve updated your shipping address/);
  });
  await check("Resolve, reopen and sidebar queue filters", async () => {
    await page.getByRole("button", { name: "Resolve", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "Reopen", exact: true }),
    ).toBeVisible();
    await page.getByRole("tab", { name: "Done", exact: true }).click();
    await expect(page.locator(".conversation-row")).toHaveCount(2);
    await page.getByRole("button", { name: "Reopen", exact: true }).click();
    await page
      .getByRole("button", { name: "AI handling 1", exact: true })
      .click();
    await expect(page.locator(".conversation-row")).toHaveCount(1);
    await expect(page.locator(".conversation-row")).toContainText(
      "Noah Williams",
    );
  });
  await check("Tablet workspace and customer drawer", async () => {
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.reload({ waitUntil: "networkidle" });
    await expect(
      page.getByRole("complementary", { name: "Customer details" }),
    ).not.toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({ path: "evidence/tablet.png" });
    await page.getByRole("button", { name: "Toggle customer details" }).click();
    await expect(
      page.getByRole("complementary", { name: "Customer details" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Close customer details" }).click();
    await expect(
      page.getByRole("complementary", { name: "Customer details" }),
    ).not.toBeVisible();
  });
  await check(
    "Mobile list, conversation, reply and customer drawer",
    async () => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.reload({ waitUntil: "networkidle" });
      await page.screenshot({ path: "evidence/mobile-inbox.png" });
      await page
        .getByRole("button", {
          name: "Sophie Chen: A small change to my order",
        })
        .click();
      await expect(
        page.getByRole("textbox", { name: "Write a reply", exact: true }),
      ).toBeVisible();
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
      await page.screenshot({ path: "evidence/mobile-conversation.png" });
      await page
        .getByRole("textbox", { name: "Write a reply", exact: true })
        .fill("Thanks Sophie!");
      await page
        .getByRole("button", { name: "Send reply", exact: true })
        .click();
      await expect(page.getByRole("log")).toContainText("Thanks Sophie!");
      await page
        .getByRole("button", { name: "Toggle customer details" })
        .click();
      await page.screenshot({ path: "evidence/mobile-customer.png" });
      await page
        .getByRole("button", { name: "Close customer details" })
        .click();
      await page.getByRole("button", { name: "Back to inbox" }).click();
      await expect(
        page.getByRole("textbox", { name: "Search conversations" }),
      ).toBeVisible();
      await page
        .getByRole("button", { name: "Open navigation", exact: true })
        .click();
      await page.getByRole("button", { name: "Email", exact: true }).click();
      await expect(page.locator(".conversation-row")).toHaveCount(4);
    },
  );
  await check("No browser errors", async () => {
    expect(errors).toEqual([]);
  });
} finally {
  await writeFile(
    "evidence/browser-checks.json",
    JSON.stringify(
      { checkedAt: new Date().toISOString(), results, errors },
      null,
      2,
    ) + "\n",
  );
  await browser.close();
}
