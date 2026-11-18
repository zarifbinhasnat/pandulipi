<p align="center">
  <img src="Resources/icon-1024.png" width="160" alt="Pandulipi icon">
</p>

<h1 align="center">Pandulipi</h1>

<p align="center"><b>Turn scanned books into EPUBs on your Mac — with Tesseract or a local AI vision model. Fully offline.</b><br>
Built with Bangla (বাংলা) books in mind, works for any language.</p>

---

*Pandulipi (পাণ্ডুলিপি) means "manuscript" in Bangla.*

## Features

- **Two OCR engines, your choice**: classic **Tesseract** (fast, CPU) or any **local vision model via [Ollama](https://ollama.com)** (e.g. Qwen3‑VL). A third engine, **PDF text**, reads an existing text layer instantly.
- **🎲 Compare on a random page**: one click picks a random page and runs Tesseract and the model **side by side**, with live timers, characters, tokens/sec, an **agreement score**, and a "model is N× slower" verdict. Use it to pick the right engine before converting a whole book.
- **Guided setup for a brand‑new Mac**: no Ollama, no Tesseract, no Homebrew? The Setup checklist detects what's missing and offers one‑click fixes (install Tesseract + Bangla, start Ollama, download the right model for your RAM). It notices when Ollama starts, without a relaunch.
- **Automatic book structure**: detects chapter and part titles, sections, **Contents**, **Index**, **Notes** and **Bibliography** pages (English and Bangla: অধ্যায়, ভূমিকা, সূচিপত্র, নির্ঘণ্ট…). The EPUB gets real chapters, a nested table of contents and reader landmarks. Running headers are removed and paragraphs/hyphenated words are rejoined across page breaks.
- **Whole‑book transcription** with **elapsed time, per‑page average, time left, and estimated finish time**. Pages stream in live as the model writes.
- **Resume anywhere**: results are saved after every page, so you can stop, quit, and pick up where you left off.
- **Review & proofread**: see each page next to its scan, fix mistakes, search across the book, or re‑run one page with a different engine.
- **EPUB 3 export** with cover (page 1), detected chapters (or every N pages), optional page markers and language metadata. Plain‑text export keeps headings as `#` lines.
- **Live RAM meter**: system memory used/total, how much the loaded model takes, app footprint, swap, and peak during a run. One click unloads the model to free RAM.
- **Model manager**: see installed models, download new ones with a progress bar, delete old ones, plus a curated list of OCR‑friendly models (🇧🇩 marks the best bets for Bangla).
- **Legacy Bangla font detection**: warns when a PDF's text layer is old Bijoy/SutonnyMJ encoding (garbage when copied) so you OCR it instead.
- Opens **PDFs or a folder of page images** (PNG, JPEG, TIFF, HEIC). Drag and drop works. Keeps your Mac awake during long runs.

## Requirements

- macOS 14 Sonoma or newer (Apple Silicon recommended)
- [Ollama](https://ollama.com/download) with at least one vision model, for the AI engine
- Tesseract with language data, for the Tesseract engine:

```bash
brew install tesseract tesseract-lang
```

## Install

1. Download `Pandulipi-*-macOS-universal.zip` from [Releases](../../releases) (runs on Apple Silicon and Intel), unzip it, and drag **Pandulipi.app** into **Applications**.
2. The app isn't notarized by Apple, so macOS blocks the first launch. Either:
   - open it once, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, or
   - run this once in Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/Pandulipi.app
     ```
3. Open Pandulipi. The **Setup** checklist on the welcome screen walks you through the rest. You need at least one engine:

| Engine | What it needs | How Pandulipi helps |
|---|---|---|
| Local AI model (best quality) | [Ollama](https://ollama.com/download) + a vision model (~3–6 GB) | Links to Ollama, starts it if installed, one‑click download of `qwen3-vl:8b` (or `:4b` on 8 GB Macs) |
| Tesseract (fast) | [Homebrew](https://brew.sh) + `tesseract tesseract-lang` | One‑click install when Homebrew is present, otherwise opens the Homebrew installer in Terminal |

**Build from source** (needs Xcode or the Command Line Tools: `xcode-select --install`):

```bash
git clone https://github.com/zarifbinhasnat/pandulipi.git
cd pandulipi
./build.sh --install
```

`./build.sh --universal --zip` makes the Apple Silicon + Intel release zip.

## Quick start

1. Start Ollama and pull a vision model, e.g. `ollama pull qwen3-vl:8b` (or use **Models → Get** inside the app).
2. Open a PDF (⌘O) or drop it on the window.
3. Press **🎲 Random Page** (⌘R) to compare Tesseract and the model on your book. If an engine is missing, its pane has an **Open Setup** button.
4. Choose the winner in the sidebar, go to **Transcribe**, press **Start** (⌘↩).
5. Proofread in **Review** (detected chapters, Contents and Index are labelled), then **Export EPUB** (⌘E).

## Which model for Bangla?

Measured on a 16 GB M‑series MacBook Air, one printed Bangla page (Kohinoor Bangla font):

| Engine | Time / page | Result |
|---|---|---|
| Tesseract 5 (`ben`) | ~0.4 s | Fast, but skipped several full lines on this font |
| `qwen3-vl:8b-instruct` (Q4) | ~50 s (19 tok/s) | Near‑perfect: 3 small character errors in ~110 words |

Recommendations:

1. **`qwen3-vl:8b`** — the best default on 16 GB Macs. Strong multilingual OCR and reading order.
2. **`qwen3-vl:4b`** — about twice as fast and half the RAM; slightly weaker on dense conjuncts.
3. **`gemma3:12b`** — broad multilingual training including Bengali; slower and tight on 16 GB.
4. **Tesseract `ben+eng`** — instant draft quality; good for clean modern prints, or as a quick first pass.

OCR‑specialist models such as `glm-ocr` and `deepseek-ocr` are very good on English/Chinese documents, but their Bangla quality is unproven, so test them with Compare first. Every book is different: always try a few random pages.

On an English history book (Kissinger's *Diplomacy*, dense 450‑word pages) `qwen3-vl:8b` took ~45–80 s per page and matched 97–99% of words against Tesseract's English output, with nothing cut off.

## Tips

- **Image size** (sidebar) trades speed for accuracy. 1600 px is a good default for models; raise it for small print.
- Use **Free RAM** after a run; Ollama otherwise keeps the model loaded for 15 minutes.
- If the RAM meter shows **swap** growing, use a smaller model or image size.
- Results cache: `~/Library/Application Support/Pandulipi/Cache/`.
- Testing without dependencies: `PANDULIPI_TESSERACT=none PANDULIPI_OLLAMA_URL=http://127.0.0.1:9 Pandulipi.app/Contents/MacOS/Pandulipi` simulates a Mac with neither engine.

## Similar projects

Pandulipi borrows good ideas from [OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF), [pdf2epub](https://pypi.org/project/pdf2epub-cli/), [local-llm-pdf-ocr](https://github.com/ahnafnafee/local-llm-pdf-ocr), [pdf-craft](https://github.com/oomol-lab/pdf-craft) and [LegacyLipi](https://pypi.org/project/legacylipi/). It differs by being a native Mac app with side‑by‑side engine comparison, live timing and memory stats, and a proofreading step.

## How it compares

| | Pandulipi | ABBYY FineReader / Adobe Acrobat | Google Drive / Lens | Online "Bangla OCR" sites |
|---|---|---|---|---|
| Price | Free, open source | ~$70–$240 per year | Free | Free with limits or paid |
| Privacy | 100% on your Mac | Local (Acrobat may use cloud) | Uploads to Google | Uploads your book |
| Bangla | Vision LLM handles conjuncts well; Tesseract `ben` as a fast option | Limited or missing (check vendor language lists) | Good, but page by page | Varies |
| Whole book → EPUB | Yes, with chapters, Contents, Index | PDF/Word focus, EPUB limited | No | Usually text/Word only |
| Pick the engine per book | Side‑by‑side compare with timing | One engine | One engine | One engine |
| Live ETA, RAM meter, resume | Yes | Partly | No | No |
| Swap in newer AI models | Any Ollama vision model | No | No | No |

## Roadmap

- Searchable PDF output (text layer under the scan)
- Bijoy → Unicode conversion of existing text layers
- Image clean‑up (deskew, contrast) before Tesseract
- Two‑page spread splitting for phone‑photographed books

## License

MIT, see [LICENSE](LICENSE).
