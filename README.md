# Ham Radio Technician Quiz

A small desktop app, written in Lazarus/Free Pascal, for practising the FCC
**Technician Class (Element 2)** amateur radio exam. It asks one
multiple-choice question at a time from the full question pool and shows the
correct answer as soon as you pick one.

## Features

- The full **2026–2030 Technician question pool**: 409 questions in
  subelements T0–T9.
- Study everything at once or filter by a single subelement, such as
  *T5 – Electrical Principles*.
- Question order and answer order are shuffled every run, so you can't
  memorise answer positions.
- Your running score and percentage are shown. The percentage turns red once
  you've missed more than 9 questions.
- The 12 T6 questions that refer to a schematic (Figures T-1, T-2 and T-3)
  open the diagram in its own window.
- The app is pool-agnostic. Swap in a different `questions.json`, such as a
  General or Extra pool in the same format, and the categories adjust
  automatically.

## Building

1. Install [Lazarus](https://www.lazarus-ide.org/). It includes Free Pascal.
2. Open `hamquiz.lpi` (**File → Open Project**).
3. Press **F9** to compile and run.

Or, from the command line:

```
lazbuild hamquiz.lpi
```

The executable looks for `questions.json` and the `images/` folder next to
itself, one folder up, or in the current directory. When you move the built
program elsewhere, copy those two items along with it.

## Project layout

| File | Purpose |
|------|---------|
| `hamquiz.lpi` | Lazarus project file |
| `hamquiz.lpr` | Program entry point |
| `umain.pas` / `umain.lfm` | Main quiz window |
| `ufigure.pas` / `ufigure.lfm` | Pop-up window for schematic diagrams |
| `questions.json` | Question pool |
| `images/` | Figures T-1, T-2, T-3 |

## Question file format

`questions.json` is an array of objects:

```json
{
  "id": "T5A05",
  "question": "…",
  "choices": ["…", "…", "…", "…"],
  "correct": 1,
  "figure": "t-1.png"
}
```

`correct` is the zero-based index into `choices`. `figure` is optional and
names a file in `images/`. The first two characters of `id` set the
subelement used for filtering.

## Question pool

The questions and figures come from the 2026–2030 Technician Class question
pool published by the NCVEC Question Pool Committee, which releases its pools
into the public domain. Answers were checked against the official pool.

## License

This project is licensed under
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). See
[LICENSE](LICENSE). The question pool and figures are public domain.
