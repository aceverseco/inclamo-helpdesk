// Signing in and finding the Orders section, shared by the end-to-end tests.
export const users = {
  admin: { email: process.env.STAND_ADMIN_EMAIL, password: process.env.STAND_ADMIN_PASSWORD },
  agent: { email: process.env.STAND_AGENT_EMAIL, password: process.env.STAND_AGENT_PASSWORD },
};

export async function signIn(page, user) {
  if (!user.email || !user.password) throw new Error('the credentials of the test user are not set');
  await page.goto('/app/login');
  await page.locator('input[type="email"], input[name="email_address"]').first().fill(user.email);
  await page.locator('input[type="password"]').first().fill(user.password);
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 45_000 });
}

// The signed-in user's interface settings, as Chatwoot keeps them per user.
// Used to have the contact sidebar and the Orders section open from the start.
export async function setUiSettings(page, settings) {
  const cookies = await page.context().cookies();
  const session = cookies.find(cookie => cookie.name === 'cw_d_session_info');
  if (!session) throw new Error('not signed in: the session cookie is missing');
  const auth = JSON.parse(decodeURIComponent(session.value));
  const headers = { 'access-token': auth['access-token'], client: auth.client, uid: auth.uid, expiry: String(auth.expiry), 'token-type': auth['token-type'] || 'Bearer' };
  const response = await page.request.put('/api/v1/profile', { headers, data: { profile: { ui_settings: settings } } });
  if (!response.ok()) throw new Error(`could not set the interface settings: HTTP ${response.status()}`);
}

// Opens a conversation and returns the Orders section of its sidebar.
export async function openOrders(page, accountId, conversationId) {
  await setUiSettings(page, { is_contact_sidebar_open: true, is_inclamo_orders_open: true });
  await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}`);
  const section = page.getByTestId('inclamo-orders-section');
  // The contact sidebar may be closed: Chatwoot's round button at the top
  // right of the conversation opens it.
  try {
    await section.waitFor({ state: 'attached', timeout: 6_000 });
  } catch (error) {
    await page.locator('button[class*="!rounded-full"]').first().click();
    await section.waitFor({ state: 'attached', timeout: 45_000 });
  }
  return section;
}
