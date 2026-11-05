import { test, expect } from '@playwright/test';
import { signIn, openOrders, users } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const conversation = process.env.E2E_CONVERSATION_ID || '1';

test('the Orders section is part of the conversation sidebar, next to the messages', async ({ page }) => {
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation);

  await expect(section).toBeVisible();
  await expect(section).not.toHaveAttribute('data-state', 'loading');
  await expect(section).toHaveAttribute('data-state', 'matched');
  await section.scrollIntoViewIfNeeded();
  await page.screenshot({ path: `${process.env.E2E_OUTPUT || 'output'}/smoke-conversation.png` });
});
