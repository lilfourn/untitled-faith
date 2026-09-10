export type ModelRoute = {
  model: string;
  providers: readonly string[];
  maxPrice?: { prompt: number; completion: number };
  reasoning?: { effort: 'low'; exclude: true } | { enabled: false };
};

type CompletionRequest = {
  provider: {
    data_collection: 'deny';
    require_parameters: true;
    max_price: { prompt: number; completion: number; request: number };
  };
  [key: string]: unknown;
};

/** Only an HTTP 429 before generation is eligible. Never replay a partial or uncertain generation. */
export async function requestWithRateLimitFallback(body: CompletionRequest,
  routes: readonly [ModelRoute, ...ModelRoute[]], apiKey: string, signal: AbortSignal): Promise<Response> {
  for (let index = 0; index < routes.length; index++) {
    signal.throwIfAborted();
    const route = routes[index]!;
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST', redirect: 'manual', signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'X-OpenRouter-Title': 'Untitled Faith' },
      body: JSON.stringify({ ...body, model: route.model,
        provider: { ...body.provider, only: route.providers,
          max_price: { ...body.provider.max_price, ...route.maxPrice } }, reasoning: route.reasoning }),
    });
    if (response.status !== 429) return response;
    const platformLimit = response.headers.has('X-RateLimit-Limit');
    console.log(JSON.stringify({ event: 'upstream_rate_limited', model: route.model,
      origin: platformLimit ? 'openrouter' : 'provider_or_unknown' }));
    // An OpenRouter-wide limit affects every model; switching cannot resolve it.
    if (platformLimit || index === routes.length - 1) return response;
    await response.body?.cancel();
    signal.throwIfAborted();
    console.log(JSON.stringify({ event: 'model_rate_limit_fallback', from: route.model, to: routes[index + 1]!.model }));
  }
  throw new Error('Missing model route');
}
