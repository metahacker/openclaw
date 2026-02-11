/**
 * Sentence boundary detector for streaming text.
 * Buffers tokens and emits complete sentences.
 */
export class SentenceDetector {
  private buffer = "";
  private timeoutHandle: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private onSentence: (sentence: string) => void,
    private config: { minLength: number; timeoutMs: number },
  ) {}

  /** Add tokens to buffer and detect complete sentences */
  addTokens(tokens: string): void {
    this.buffer += tokens;

    if (this.timeoutHandle) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = null;
    }

    this.extractSentences();

    if (this.buffer.length > 0) {
      this.timeoutHandle = setTimeout(() => this.flush(), this.config.timeoutMs);
    }
  }

  private extractSentences(): void {
    // Match sentence endings: . ! ? followed by whitespace or end
    // But skip common abbreviations like Mr. Dr. etc.
    const regex = /([.!?])(\s+|$)/g;
    let lastIndex = 0;
    let match: RegExpExecArray | null;

    while ((match = regex.exec(this.buffer)) !== null) {
      const endIndex = match.index + match[0].length;
      const sentence = this.buffer.slice(lastIndex, endIndex).trim();

      if (sentence.length >= this.config.minLength) {
        this.onSentence(sentence);
        lastIndex = endIndex;
      }
    }

    this.buffer = this.buffer.slice(lastIndex);
  }

  /** Flush remaining buffer as final sentence */
  flush(): void {
    if (this.timeoutHandle) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = null;
    }
    if (this.buffer.trim().length > 0) {
      this.onSentence(this.buffer.trim());
      this.buffer = "";
    }
  }
}
