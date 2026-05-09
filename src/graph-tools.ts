/**
 * graph-tools.ts — Microsoft Graph API tools
 *
 * These tools are surfaced to the LLM by OpenClaw when the agent
 * processes a message. They operate under the agent's Agentic Identity
 * (AGENT_IDENTITY), accessing only resources explicitly shared with it.
 *
 * Auth: T1 → T2 → Agent token flow (Federated Identity Credentials)
 * Ref: https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity
 *
 * Tools match SidU/openclaw-a365 reference implementation:
 *   get_calendar_events, create_calendar_event, update_calendar_event,
 *   delete_calendar_event, find_meeting_times, send_email, get_user_info
 */

import { ClientSecretCredential } from "@azure/identity";
import { config } from "./config";

let _credential: ClientSecretCredential | null = null;

function getCredential(): ClientSecretCredential {
  if (!_credential) {
    _credential = new ClientSecretCredential(
      config.a365TenantId,
      config.a365AppId,
      config.a365AppPassword
    );
  }
  return _credential;
}

/**
 * Acquire a Graph API token for the agent's identity via the T1→T2→Agent
 * Federated Identity Credential (FIC) exchange.
 *
 * Full production implementation:
 *   T1: client_credentials with fmi_path scoped to AA_INSTANCE_ID
 *   T2: jwt-bearer assertion on the T1 token
 *   Agent: user_fic grant using T2 for the AGENT_IDENTITY UPN
 *
 * TODO: Implement full FIC chain once Microsoft Agent 365 SDK FIC
 * helpers are published. Track: https://github.com/microsoft/Agent365-nodejs
 */
async function getAgentGraphToken(): Promise<string> {
  const credential = getCredential();
  const tokenResponse = await credential.getToken(
    "https://graph.microsoft.com/.default"
  );
  if (!tokenResponse) {
    throw new Error("[graph] Failed to acquire token");
  }
  // TODO: exchange tokenResponse.token through T2 → Agent FIC flow
  return tokenResponse.token;
}

async function graphFetch(
  path: string,
  method = "GET",
  body?: unknown
): Promise<unknown> {
  const token = await getAgentGraphToken();
  const response = await fetch(`https://graph.microsoft.com/v1.0${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`[graph] ${method} ${path} → ${response.status}: ${text}`);
  }

  return response.status === 204 ? null : response.json();
}

// ─── Calendar Tools ─────────────────────────────────────────────────────────

export async function getCalendarEvents(
  startDateTime: string,
  endDateTime: string
): Promise<unknown> {
  // Reads from the calendar shared with AGENT_IDENTITY (the agent's own identity)
  const user = encodeURIComponent(config.agentIdentity);
  const params = new URLSearchParams({ startDateTime, endDateTime, $top: "20" });
  return graphFetch(`/users/${user}/calendarView?${params}`);
}

export async function createCalendarEvent(event: {
  subject: string;
  start: { dateTime: string; timeZone: string };
  end: { dateTime: string; timeZone: string };
  attendees?: { emailAddress: { address: string; name?: string }; type: string }[];
  body?: { contentType: string; content: string };
}): Promise<unknown> {
  const user = encodeURIComponent(config.agentIdentity);
  return graphFetch(`/users/${user}/events`, "POST", event);
}

export async function updateCalendarEvent(
  eventId: string,
  updates: Partial<{
    subject: string;
    start: { dateTime: string; timeZone: string };
    end: { dateTime: string; timeZone: string };
  }>
): Promise<unknown> {
  const user = encodeURIComponent(config.agentIdentity);
  return graphFetch(`/users/${user}/events/${eventId}`, "PATCH", updates);
}

export async function deleteCalendarEvent(eventId: string): Promise<void> {
  const user = encodeURIComponent(config.agentIdentity);
  await graphFetch(`/users/${user}/events/${eventId}`, "DELETE");
}

export async function findMeetingTimes(request: {
  attendees: { emailAddress: { address: string }; type: string }[];
  meetingDuration: string;
  timeConstraint: {
    activityDomain: string;
    timeSlots: { start: { dateTime: string; timeZone: string }; end: { dateTime: string; timeZone: string } }[];
  };
}): Promise<unknown> {
  return graphFetch("/me/findMeetingTimes", "POST", request);
}

// ─── Mail Tools ─────────────────────────────────────────────────────────────

export async function sendEmail(message: {
  subject: string;
  body: { contentType: "Text" | "HTML"; content: string };
  toRecipients: { emailAddress: { address: string; name?: string } }[];
  ccRecipients?: { emailAddress: { address: string; name?: string } }[];
}): Promise<void> {
  const user = encodeURIComponent(config.agentIdentity);
  await graphFetch(`/users/${user}/sendMail`, "POST", { message });
}

// ─── User Tools ─────────────────────────────────────────────────────────────

export async function getUserInfo(upn: string): Promise<unknown> {
  return graphFetch(`/users/${encodeURIComponent(upn)}`);
}

export const graphTools = {
  getCalendarEvents,
  createCalendarEvent,
  updateCalendarEvent,
  deleteCalendarEvent,
  findMeetingTimes,
  sendEmail,
  getUserInfo,
};
