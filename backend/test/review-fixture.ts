import { REVIEW_MODEL, type ReviewDecision } from '../src/request-review';

export function reviewCompletion(decision: ReviewDecision = 'answer') {
  return Response.json({ id: 'review-generation', usage: { cost: 0.0001, prompt_tokens: 10, completion_tokens: 3 },
    choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ decision }) } }] });
}

// Existing answer-adapter tests control the second call independently of review.
export function withApprovedReview(answerFetch: typeof fetch): typeof fetch {
  return (input, init) => {
    if (typeof init?.body === 'string' && JSON.parse(init.body).model === REVIEW_MODEL) {
      return Promise.resolve(reviewCompletion());
    }
    return answerFetch(input, init);
  };
}
