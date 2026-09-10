import { bible } from './data';

const STOP = new Set(('a an and are as at be been being but by can could did do does for from had has have how i if in into is it its '
  + 'me my of on or our should that the their them there these they this those to us was we were what when where which who why '
  + 'will with would you your about bible biblical scripture scriptures verse verses passage passages chapter chapters explain '
  + 'tell say says mean meaning please help understand according teach teaches teaching').split(' '));

// Transparent vocabulary expansion, not generated doctrine or a semantic model.
const GROUPS = [
  'anxiety anxious worry worried worries worrying', 'fear afraid fearful frightened scared',
  'forgive forgiveness forgives forgiven forgiving', 'pray prayer prayers praying prayed',
  'suffer suffering suffers suffered affliction afflicted', 'grief grieve grieving mourn mourning sorrow',
  'hope hopes hopeful', 'faith faithful faithfulness trust trusting', 'love loves loved loving',
  'anger angry wrath', 'repent repentance repented', 'baptism baptize baptized',
  'salvation save saves saved saving', 'resurrection resurrected risen raised',
  'lonely loneliness alone', 'temptation tempt tempted', 'generosity generous giving give',
  'money wealth wealthy rich riches', 'justice unjust injustice', 'peace peaceful',
  'wisdom wise', 'marriage married marry husband wife', 'humility humble',
  'forgiveness mercy merciful', 'creation create created creator', 'death die died dead',
];

export function searchTerms(query: string): Map<string, number> {
  const terms = new Map<string, number>();
  for (const term of query.toLowerCase().match(/[a-z]+/g) ?? []) {
    if (term.length > 2 && !STOP.has(term)) terms.set(term, 1);
    if (terms.size >= 20) break;
  }
  const original = [...terms.keys()];
  for (const word of original) {
    const variants = word.endsWith('s') ? [word.slice(0, -1)] : [word + 's'];
    for (const group of GROUPS) {
      const words = group.split(' ');
      if (words.includes(word)) variants.push(...words);
    }
    for (const variant of variants) if (!terms.has(variant) && Object.hasOwn(bible.postings, variant)) terms.set(variant, .45);
  }
  return terms;
}

/** BM25 over prebuilt posting lists; never scans or embeds the full text on a request. */
export function searchBible(query: string, limit = 30): { index: number; score: number }[] {
  const scores = new Map<number, number>();
  const count = bible.verses.length;
  for (const [term, weight] of searchTerms(query)) {
    const postings = Object.hasOwn(bible.postings, term) ? bible.postings[term] : undefined;
    if (!postings) continue;
    const frequency = postings.length / 2;
    const inverse = Math.log(1 + (count - frequency + .5) / (frequency + .5));
    for (let offset = 0; offset < postings.length; offset += 2) {
      const index = postings[offset]!, tf = postings[offset + 1]!;
      const normalization = 1.2 * (.25 + .75 * bible.lengths[index]! / bible.averageLength);
      const score = weight * inverse * tf * 2.2 / (tf + normalization);
      scores.set(index, (scores.get(index) ?? 0) + score);
    }
  }
  return [...scores].map(([index, score]) => ({ index, score }))
    .sort((a, b) => b.score - a.score || a.index - b.index).slice(0, Math.max(0, Math.min(limit, 100)));
}
