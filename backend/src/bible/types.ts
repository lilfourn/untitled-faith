export type BibleData = {
  translation: { id: string; name: string; license: string; notice: string; source: string };
  sourceSHA256: string;
  books: { id: number; name: string; chapters: number; aliases: string[]; code: string }[];
  verses: [number, string][];
  lengths: number[];
  averageLength: number;
  postings: Record<string, number[]>;
};

export type BiblePassage = { reference: string; translation: 'BSB' | 'ESV'; url: string; text: string };
export type BibleContext = { passages: BiblePassage[]; limited: boolean };

// Count the serialized context, including metadata, against the input budget.
export const MAX_BIBLE_CONTEXT_CHARACTERS = 12000;
export const MAX_BIBLE_PASSAGES = 6;
