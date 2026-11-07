import settingsPages from '../settingsPages';

// The pages themselves import Chatwoot's settings frame, which leads back to
// Chatwoot's settings routes and so to this list: they are stood in for here.
vi.mock('../components/AiAgentPage.vue', () => ({ default: { __name: 'AiAgentPage' } }));
vi.mock('../components/OrderRolesPage.vue', () => ({ default: { __name: 'OrderRolesPage' } }));

describe('settings pages of the overlay', () => {
  it('give the AI agent page to administrators only', () => {
    const page = settingsPages.find(entry => entry.path === 'ai-agent');

    expect(page.name).toBe('inclamo_ai_agent');
    expect(page.permissions).toEqual(['administrator']);
    expect(page.label()).toBe('AI agent');
    expect(page.component.__name).toBe('AiAgentPage');
  });

  it('keep the order actions page for administrators only', () => {
    const page = settingsPages.find(entry => entry.path === 'order-actions');

    expect(page.permissions).toEqual(['administrator']);
  });
});
