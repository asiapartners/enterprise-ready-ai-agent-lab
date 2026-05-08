/**
 * OpenClaw A365 (Microsoft 365 Agents) channel plugin.
 * Registers the a365 channel with Graph API tools for calendar, email, and user operations.
 */
import { a365Channel } from "./src/channel.js";

// Plugin registration object consumed by OpenClaw's plugin loader
export default {
  id: "a365",
  channels: [a365Channel],
};

// Re-export public API for advanced use cases
export { monitorA365Provider } from "./src/monitor.js";
export { createGraphTools } from "./src/graph-tools.js";
export { sendMessageA365, sendAdaptiveCardA365, a365Outbound } from "./src/outbound.js";
export {
  saveConversationReference,
  getConversationReference,
  getConversationReferenceByUserAadId,
  listConversationReferences,
  deleteConversationReference,
} from "./src/conversation-store.js";
export { setA365Runtime, getA365Runtime } from "./src/runtime.js";
export { resolveGraphTokenConfig, getGraphToken, invalidateGraphTokenCache } from "./src/token.js";

// Type exports
export type { A365Config, A365MessageMetadata, GraphCalendarEvent, StoredConversationReference } from "./src/types.js";
