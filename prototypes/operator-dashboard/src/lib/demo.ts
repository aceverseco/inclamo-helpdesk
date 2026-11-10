export type Channel = "Email" | "Live chat" | "Instagram";
export type Status = "open" | "snoozed" | "done";
export type Queue = "all" | "mine" | "unassigned" | "ai" | Channel;
export interface Message {
  id: number;
  kind: "customer" | "agent" | "note";
  text: string;
  time: string;
  author?: string;
}
export interface Conversation {
  id: number;
  name: string;
  initials: string;
  tone: string;
  email: string;
  subject: string;
  preview: string;
  time: string;
  channel: Channel;
  unread: boolean;
  priority: boolean;
  assignee: string;
  status: Status;
  tag: string;
  messages: Message[];
  draft: string;
  noteDraft: string;
}

export const demoConversations: Conversation[] = [
  {
    id: 1048,
    name: "Sophie Chen",
    initials: "SC",
    tone: "peach",
    email: "sophie.chen@example.com",
    subject: "A small change to my order",
    preview: "Thanks! The new address is 24 Maple…",
    time: "2m",
    channel: "Email",
    unread: true,
    priority: true,
    assignee: "You",
    status: "open",
    tag: "Order update",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "Hi there! I just placed order #1048, but I noticed I used my old address. Is there still time to change it? 🙈",
        time: "10:24 AM",
      },
      {
        id: 2,
        kind: "agent",
        text: "Hi Sophie! Of course — your order hasn’t shipped yet, so we can help with that. Could you send me the new delivery address?",
        time: "10:26 AM",
      },
      {
        id: 3,
        kind: "customer",
        text: "Thanks! The new address is 24 Maple Street, Brooklyn, NY 11201. Really appreciate the quick help!",
        time: "10:28 AM",
      },
    ],
  },
  {
    id: 1047,
    name: "James Wilson",
    initials: "JW",
    tone: "sky",
    email: "james.w@example.com",
    subject: "Where is my package?",
    preview: "It says delivered, but I haven’t received it.",
    time: "8m",
    channel: "Live chat",
    unread: true,
    priority: true,
    assignee: "You",
    status: "open",
    tag: "Delivery",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "Hello! My tracking says delivered, but I haven’t received the package. Could you help me check?",
        time: "10:22 AM",
      },
    ],
  },
  {
    id: 1046,
    name: "Emma Thompson",
    initials: "ET",
    tone: "mist",
    email: "emma.t@example.com",
    subject: "Love the new collection",
    preview: "Does the weekend bag come in olive?",
    time: "12m",
    channel: "Instagram",
    unread: true,
    priority: false,
    assignee: "Mia",
    status: "open",
    tag: "Product question",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "Love the new collection! Does the weekend bag come in olive? I can only see the black one online.",
        time: "10:18 AM",
      },
    ],
  },
  {
    id: 1045,
    name: "Oliver Martin",
    initials: "OM",
    tone: "navy",
    email: "oliver.m@example.com",
    subject: "Exchange for another size",
    preview: "You: Absolutely, happy to help with that.",
    time: "24m",
    channel: "Email",
    unread: false,
    priority: false,
    assignee: "You",
    status: "open",
    tag: "Exchange",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "My new overshirt is a little snug. Can I exchange it for a size L?",
        time: "9:58 AM",
      },
      {
        id: 2,
        kind: "agent",
        text: "Absolutely, happy to help with that. Is the item still unworn with its original tags?",
        time: "10:06 AM",
      },
    ],
  },
  {
    id: 1044,
    name: "Isabella Rossi",
    initials: "IR",
    tone: "orange",
    email: "isabella.r@example.com",
    subject: "A gift for my sister",
    preview: "Can you include a little gift note?",
    time: "38m",
    channel: "Live chat",
    unread: false,
    priority: false,
    assignee: "Unassigned",
    status: "open",
    tag: "Gift order",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "I’m ordering a gift for my sister. Can you include a little gift note and leave the price off the packing slip?",
        time: "9:52 AM",
      },
    ],
  },
  {
    id: 1043,
    name: "Noah Williams",
    initials: "NW",
    tone: "peach",
    email: "noah.w@example.com",
    subject: "Shipping to Canada",
    preview: "AI: We ship to Canada in 5–7 business days.",
    time: "46m",
    channel: "Email",
    unread: false,
    priority: false,
    assignee: "Inclamo AI",
    status: "open",
    tag: "AI handling",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "Do you ship to Toronto? I’m looking to order the everyday tote.",
        time: "9:42 AM",
      },
      {
        id: 2,
        kind: "agent",
        text: "Yes! We ship to Canada in 5–7 business days. Shipping rates are shown at checkout.",
        time: "9:44 AM",
        author: "Inclamo AI",
      },
    ],
  },
  {
    id: 1042,
    name: "Ava Johnson",
    initials: "AJ",
    tone: "sky",
    email: "ava.j@example.com",
    subject: "Thank you for your help!",
    preview: "This is exactly what I was looking for 💚",
    time: "1h",
    channel: "Instagram",
    unread: false,
    priority: false,
    assignee: "Mia",
    status: "open",
    tag: "Feedback",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "This is exactly what I was looking for 💚 Thank you for helping me choose!",
        time: "9:30 AM",
      },
    ],
  },
  {
    id: 1041,
    name: "Lucas Brown",
    initials: "LB",
    tone: "navy",
    email: "lucas.b@example.com",
    subject: "Invoice request",
    preview: "Could I get an invoice for my last order?",
    time: "2h",
    channel: "Email",
    unread: false,
    priority: false,
    assignee: "Unassigned",
    status: "open",
    tag: "Billing",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "Could I get an invoice for my last order? It’s for our company’s records. Thanks!",
        time: "8:30 AM",
      },
    ],
  },
  {
    id: 1040,
    name: "Charlotte Lee",
    initials: "CL",
    tone: "mist",
    email: "charlotte.l@example.com",
    subject: "Waiting for a return label",
    preview: "You: I’ll check back with you tomorrow.",
    time: "1d",
    channel: "Email",
    unread: false,
    priority: false,
    assignee: "You",
    status: "snoozed",
    tag: "Return",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "agent",
        text: "Your return label is being prepared. I’ll check back with you tomorrow.",
        time: "Yesterday",
      },
    ],
  },
  {
    id: 1039,
    name: "Henry Davis",
    initials: "HD",
    tone: "peach",
    email: "henry.d@example.com",
    subject: "All sorted, thank you",
    preview: "The replacement arrived. Perfect!",
    time: "1d",
    channel: "Live chat",
    unread: false,
    priority: false,
    assignee: "You",
    status: "done",
    tag: "Resolved",
    draft: "",
    noteDraft: "",
    messages: [
      {
        id: 1,
        kind: "customer",
        text: "The replacement arrived. Perfect! Thank you for sorting it out so quickly.",
        time: "Yesterday",
      },
    ],
  },
];

export const aiSuggestions: Record<number, string> = {
  1048: "Hi Sophie, thanks for sending the new address! Your order is still awaiting dispatch. I’ll update the shipping address to 24 Maple Street, Brooklyn, NY 11201 and confirm once it’s saved.",
  1047: "Hi James, I’m sorry your package hasn’t arrived. Could you confirm the order number and delivery address so I can check with the carrier?",
  1046: "Hi Emma! Thanks for the lovely feedback. Let me check availability of the weekend bag in olive for you.",
};
