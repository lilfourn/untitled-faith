import type { Message } from './contract';

export const FIRST_RESPONSE_PREAMBLE = "Growing as a Christian includes seeking answers through prayer, sanctification (becoming more like Christ), and counsel from other believers. Please don't let this app replace these essential parts of your Christian life. Before we continue, take a moment to pray and ask God to reveal His truth and guide your understanding.";

export function conversationOpeningPrompt(messages: readonly Message[]): string {
  if (messages.some(message => message.role === 'assistant')) {
    return `Conversation opening: this thread already has an assistant response. Do not repeat or paraphrase the first-response preamble or routinely ask the user to pray before continuing. Answer the current request using the usual teaching and writing guidance. Discuss prayer, sanctification, other believers, or the app's limitations when relevant to the actual question, without repeating an introductory reminder.`;
  }

  return `Conversation opening: this is the first assistant response in this thread. For decision answer, begin the answer string with the following preamble as one ordinary paragraph, before any Scripture, heading, greeting, or explanation:
${FIRST_RESPONSE_PREAMBLE}
Then add a blank line and answer the user's request in the same response, following the usual verse-then-explanation guidance when substantive. This first-response preamble takes precedence over instructions to start with Scripture or answer greetings directly. Invite prayer without requiring confirmation, withholding the answer, or assuming the user has prayed. Do not claim that God will provide an immediate answer, that your answer is divine revelation, or that you have prayed for the user. Respect any stated doubt or unbelief; the invitation must not require belief. For off_topic, unsafe, or crisis, retain the required empty answer string and do not add this preamble.`;
}
