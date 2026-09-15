import type { ModelRoute } from './model-routing';

// Server-owned order. Fallbacks run only after an unbilled HTTP rate-limit rejection.
export const ANSWER_ROUTES = [
  // Vertex is returning rate-limit errors during server-tool synthesis (September 15).
  // Keep the same model on AI Studio; do not replay a partially billed generation.
  { model: 'google/gemini-3.8-flash', providers: ['google-ai-studio'], reasoning: { effort: 'low', exclude: true } },
  { model: 'openai/gpt-5.6-luna', providers: ['openai'], reasoning: { effort: 'low', exclude: true },
    maxPrice: { prompt: 0.4, completion: 1.8 } },
] as const satisfies readonly [ModelRoute, ...ModelRoute[]];
