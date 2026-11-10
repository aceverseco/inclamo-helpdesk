<script setup lang="ts">
import { ref } from "vue";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  ChevronDown,
  ChevronUp,
  Mail,
  MapPin,
  ShoppingBag,
  Package,
  ArrowUpRight,
  Sparkles,
  Plus,
  X,
  Check,
  Truck,
  Pencil,
  ExternalLink,
  Clock3,
  BookOpen as BookIcon,
} from "lucide-vue-next";
import PersonAvatar from "./PersonAvatar.vue";
import IconButton from "./IconButton.vue";
import type { Conversation } from "@/lib/demo";

defineProps<{
  conversation: Conversation;
  addressUpdated: boolean;
  tab: string;
}>();
const emit = defineEmits<{
  close: [];
  tab: [value: string];
  order: [];
  address: [];
  tag: [];
  suggest: [];
  copy: [value: string];
  knowledge: [];
}>();
const orderExpanded = ref(true);
const activityExpanded = ref(false);
</script>

<template>
  <aside class="customer-panel" aria-label="Customer details">
    <Tabs :model-value="tab" @update:model-value="emit('tab', String($event))">
      <div class="customer-tabs-bar">
        <TabsList class="customer-tabs"
          ><TabsTrigger value="details">Details</TabsTrigger
          ><TabsTrigger value="copilot"
            ><Sparkles />Copilot</TabsTrigger
          ></TabsList
        ><IconButton label="Close customer details" @click="emit('close')"
          ><X
        /></IconButton>
      </div>
      <TabsContent value="details" class="customer-scroll">
        <div class="customer-profile">
          <div class="profile-avatar-wrap">
            <PersonAvatar
              :initials="conversation.initials"
              :tone="conversation.tone"
              large
            /><span class="profile-status"><Check /></span>
          </div>
          <h3>{{ conversation.name }}</h3>
          <p>
            Customer since
            {{ conversation.id === 1048 ? "March 2025" : "November 2026" }}
          </p>
          <Badge
            v-if="conversation.id === 1048"
            variant="outline"
            class="returning-badge"
            ><span />Returning customer</Badge
          >
          <div class="customer-contact">
            <button @click="emit('copy', conversation.email)">
              <Mail /><span>{{ conversation.email }}</span>
            </button>
            <div v-if="conversation.id === 1048">
              <MapPin /><span
                >Brooklyn, New York
                <span class="local-time">10:30 AM</span></span
              >
            </div>
          </div>
        </div>
        <div v-if="conversation.id === 1048" class="customer-stats">
          <div><strong>4</strong><span>Orders</span></div>
          <div><strong>$328.00</strong><span>Lifetime value</span></div>
          <div><strong>1 year</strong><span>With us</span></div>
        </div>
        <section class="customer-section tags-section">
          <div class="section-title">
            <h4>Tags</h4>
            <IconButton label="Manage customer tags" @click="emit('tag')"
              ><Plus
            /></IconButton>
          </div>
          <div class="tag-list">
            <Badge variant="secondary">{{ conversation.tag }}</Badge
            ><Badge v-if="conversation.id === 1048" variant="outline"
              >VIP customer</Badge
            >
          </div>
        </section>
        <section class="customer-section order-section">
          <div class="section-title">
            <h4>
              <ShoppingBag class="shopify-icon" />Store orders<span
                class="section-count"
                >{{ conversation.id === 1048 ? 4 : 0 }}</span
              >
            </h4>
            <span class="store-source">Shopify</span>
          </div>
          <div v-if="conversation.id === 1048" class="order-card">
            <button
              class="order-card-heading"
              :aria-expanded="orderExpanded"
              @click="orderExpanded = !orderExpanded"
            >
              <span
                ><strong>#1048</strong
                ><small>Nov 10, 2026 · 9:58 AM</small></span
              ><span class="order-total"
                >$89.00<ChevronUp v-if="orderExpanded" /><ChevronDown v-else
              /></span>
            </button>
            <div v-if="orderExpanded" class="order-card-body">
              <div class="order-badges">
                <span class="paid"><i />Paid</span
                ><span class="unfulfilled"><i />Unfulfilled</span>
              </div>
              <div class="order-product">
                <div class="product-image">
                  <svg viewBox="0 0 56 64" aria-hidden="true">
                    <path d="M10 23h36l4 34H6z" fill="#c2b6a0" />
                    <path d="M11 24h34l3 32H8z" fill="#d3c9b6" />
                    <path
                      d="M19 25V15c0-12 18-12 18 0v10"
                      fill="none"
                      stroke="#a99d87"
                      stroke-width="3"
                    />
                    <path
                      d="M16 24v31m24-31v31"
                      stroke="#b9ad97"
                      stroke-width=".7"
                    />
                    <rect
                      x="22"
                      y="36"
                      width="12"
                      height="10"
                      rx="1"
                      fill="#ece5d8"
                    />
                    <text
                      x="28"
                      y="43"
                      font-size="6"
                      text-anchor="middle"
                      fill="#55534b"
                      font-family="serif"
                    >
                      n°
                    </text>
                  </svg>
                </div>
                <div>
                  <strong>Everyday Tote</strong><span>Natural / One size</span
                  ><small>Qty 1 <span>$89.00</span></small>
                </div>
              </div>
              <div class="shipping-row">
                <Truck />
                <div>
                  <strong>Standard delivery</strong
                  ><span>Estimated Nov 13–15</span>
                </div>
              </div>
              <div class="order-address">
                <div>
                  <span>Shipping address</span
                  ><button
                    aria-label="Edit shipping address"
                    @click="emit('address')"
                  >
                    <Pencil />
                  </button>
                </div>
                <p>
                  {{ addressUpdated ? "24 Maple Street" : "112 Bedford Avenue"
                  }}<br />Brooklyn, NY {{ addressUpdated ? "11201" : "11211" }}
                </p>
                <span v-if="addressUpdated" class="address-saved"
                  ><Check />Updated in preview</span
                >
              </div>
              <Button
                variant="outline"
                size="sm"
                class="view-order-button"
                @click="emit('order')"
                >View order<ArrowUpRight
              /></Button>
            </div>
          </div>
          <div v-else class="no-orders">
            <Package />
            <p>No orders linked to this conversation.</p>
          </div>
          <button
            v-if="conversation.id === 1048"
            class="previous-orders"
            @click="emit('order')"
          >
            View all 4 orders<ChevronDown />
          </button>
        </section>
        <section class="customer-section activity-section">
          <button
            class="section-title activity-toggle"
            :aria-expanded="activityExpanded"
            @click="activityExpanded = !activityExpanded"
          >
            <h4>Recent activity</h4>
            <ChevronUp v-if="activityExpanded" /><ChevronDown v-else />
          </button>
          <div v-if="activityExpanded" class="activity-list">
            <p>
              <Clock3 /><span
                >Conversation opened<small>Today, 10:24 AM</small></span
              >
            </p>
            <p v-if="conversation.id === 1048">
              <ShoppingBag /><span
                >Placed order #1048<small>Today, 9:58 AM</small></span
              >
            </p>
          </div>
        </section>
        <div class="customer-footer">
          <span class="connected-dot" />Store data synced<span>Just now</span>
        </div>
      </TabsContent>
      <TabsContent value="copilot" class="copilot-content"
        ><span class="copilot-hero"><Sparkles /></span>
        <h3>A second pair of eyes.</h3>
        <p>Everything you need for a thoughtful reply, in one place.</p>
        <div class="copilot-summary">
          <span class="eyebrow">CONVERSATION SUMMARY</span>
          <p v-if="conversation.id === 1048">
            Sophie wants to update her delivery address. Order #1048 is paid and
            hasn’t shipped. She’s shared the new address in her last message.
          </p>
          <p v-else>
            {{ conversation.name }} is asking about “{{
              conversation.subject.toLowerCase()
            }}”. Review the conversation before replying.
          </p>
        </div>
        <div class="copilot-next">
          <h4>Suggested next step</h4>
          <p>
            {{
              conversation.id === 1048
                ? "Update the shipping address, then confirm the change with Sophie."
                : "Check the customer’s details and send a helpful reply."
            }}
          </p>
          <Button
            v-if="conversation.id === 1048"
            variant="outline"
            @click="emit('address')"
            ><Pencil />Review address</Button
          ><Button @click="emit('suggest')"
            ><Sparkles />Use example draft</Button
          >
        </div>
        <div class="copilot-source">
          <BookIcon /><button @click="emit('knowledge')">
            Shipping & order changes<ExternalLink />
          </button>
        </div>
        <small class="copilot-disclaimer"
          >Example suggestions for this design preview.<br />Review all details
          before sending.</small
        ></TabsContent
      >
    </Tabs>
  </aside>
</template>
