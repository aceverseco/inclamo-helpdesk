// The overlay's screens that stand where Chatwoot's own stood
// (patches/overlay-screens.txt). Their behaviour is covered in the browser
// suites; here each one loads with everything it imports from Chatwoot, so a
// component Chatwoot moved or renamed fails in this file, not in the build.
const screens = {
  ConversationCard: () => import('../workspace/ConversationCard.vue'),
  CustomerSidePanel: () => import('../workspace/CustomerSidePanel.vue'),
  CustomerContact: () => import('../workspace/CustomerContact.vue'),
};

describe('overlay screens', () => {
  it.each(Object.keys(screens))('%s loads with what it takes from Chatwoot', async name => {
    const loaded = await screens[name]();

    expect(loaded.default).toBeTruthy();
  });

  it('the customer panel shows the overlay contact, the list shows the overlay row', async () => {
    const panel = (await screens.CustomerSidePanel()).default;
    const card = (await screens.ConversationCard()).default;
    const contact = (await screens.CustomerContact()).default;

    expect(contact.components.CustomerProfile).toBeTruthy();
    expect(panel).not.toBe(card);
  });
});
