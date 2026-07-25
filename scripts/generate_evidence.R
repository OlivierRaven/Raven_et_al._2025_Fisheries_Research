# Generates evidence.json: a manifest linking every crossref-citable
# fig-/tbl- claim in index.qmd to the exact analysis.qmd chunk that
# produced it, the data it reads, and the outputs it writes.
#
# Join key: the Quarto cross-reference label (e.g. "tbl-rf") is the same
# string in both files, so no new annotation scheme is needed beyond
# what Quarto authors already write.
#
# Run this after a successful `quarto render` — evidenceGeneratedAt is
# treated downstream as "last verified reproducible".

if (!requireNamespace("here", quietly = TRUE)) stop("here package required")
repo_root <- here::here()

analysis_lines <- readLines(file.path(repo_root, "analysis.qmd"), warn = FALSE)
index_lines <- readLines(file.path(repo_root, "index.qmd"), warn = FALSE)
index_text <- paste(index_lines, collapse = "\n")
# Drop HTML comments so disabled/commented-out embeds and citations
# (e.g. <!--{{< embed analysis.qmd#fig-x >}}-->) are not treated as live.
index_text <- gsub("<!--.*?-->", "", index_text, perl = TRUE)

github_repo <- "OlivierRaven/Raven_et_al._2025_Fisheries_Research"
git_ref <- tryCatch(
  trimws(system("git rev-parse HEAD", intern = TRUE)),
  error = function(e) "main"
)

# ---- find every fig-/tbl- labelled chunk in analysis.qmd ----
label_lines <- grep('^#\\|\\s*label:\\s*(fig|tbl)-', analysis_lines)

extract_chunk <- function(label_line_idx) {
  # walk backwards to the opening ```{r}
  start <- label_line_idx
  while (start > 1 && !grepl("^```\\{r", analysis_lines[start])) start <- start - 1
  # walk forwards to the closing ```
  end <- label_line_idx
  while (end < length(analysis_lines) && analysis_lines[end] != "```") end <- end + 1
  list(start = start, end = end)
}

get_opt <- function(body, name) {
  m <- regmatches(body, regexpr(paste0('#\\|\\s*', name, ':\\s*"([^"]*)"'), body))
  if (length(m) == 0 || m == "") return(NA_character_)
  sub(paste0('#\\|\\s*', name, ':\\s*"([^"]*)"'), "\\1", m)
}

find_files <- function(body, fn_pattern, ext_pattern) {
  m <- gregexpr(paste0(fn_pattern, '\\(\\s*"([^"]+', ext_pattern, ')"'), body, perl = TRUE)
  matches <- regmatches(body, m)[[1]]
  unique(gsub(paste0('.*"([^"]+', ext_pattern, ')".*'), "\\1", matches))
}

entries <- list()

for (idx in label_lines) {
  label <- sub('^#\\|\\s*label:\\s*', "", analysis_lines[idx])
  bounds <- extract_chunk(idx)
  body <- paste(analysis_lines[bounds$start:bounds$end], collapse = "\n")

  tbl_cap <- get_opt(body, "tbl-cap")
  fig_cap <- get_opt(body, "fig-cap")
  caption <- if (!is.na(tbl_cap)) tbl_cap else fig_cap

  reads <- unique(c(
    find_files(body, "read_excel", "\\.xlsx"),
    find_files(body, "read\\.csv|read_csv", "\\.csv"),
    find_files(body, "readRDS", "\\.rds")
  ))
  reads <- reads[!is.na(reads)]

  writes <- unique(regmatches(
    body,
    gregexpr('file\\.path\\(out_dir,\\s*"\\s*([^"]+\\.(csv|png|rds))"\\)', body, perl = TRUE)
  )[[1]])
  writes <- trimws(gsub('file\\.path\\(out_dir,\\s*"\\s*([^"]+)"\\)', "\\1", writes))

  # does index.qmd embed or cite this label?
  # Negative lookahead guards against e.g. "tbl-element-selection" matching
  # inside "@tbl-element-selection-static" — a plain \b is not enough here
  # because "-" is a non-word character and still satisfies \b.
  embedded <- grepl(paste0("\\{\\{<\\s*embed\\s+analysis\\.qmd#", label, "\\s*>\\}\\}"), index_text)
  cited <- grepl(paste0("@", label, "(?![A-Za-z0-9_-])"), index_text, perl = TRUE)
  if (!embedded && !cited) next  # not surfaced in the manuscript — skip (see: orphaned labels)

  # best-effort claim sentence: paragraph containing the first @label, split to the sentence with it
  label_boundary <- "(?![A-Za-z0-9_-])"
  claim_text <- NA_character_
  para_match <- regexpr(paste0("[^\n]*@", label, label_boundary, "[^\n]*"), index_text, perl = TRUE)
  if (para_match > 0) {
    para <- regmatches(index_text, para_match)
    sentences <- strsplit(para, "(?<=[.?!])\\s+", perl = TRUE)[[1]]
    hit <- sentences[grepl(paste0("@", label, label_boundary), sentences, perl = TRUE)]
    if (length(hit)) {
      claim_text <- trimws(gsub(paste0("\\(?@", label, label_boundary, "\\)?"), "", hit[1], perl = TRUE))
      # inline computed values (`r accuracy_rf`) can't be evaluated by this
      # static parser — mark them as a placeholder rather than leak raw code
      claim_text <- gsub("`r [^`]+`", "[computed value]", claim_text, perl = TRUE)
      claim_text <- gsub("\\s+", " ", claim_text)
    }
  }

  entries[[length(entries) + 1]] <- list(
    label = label,
    manuscriptRef = paste0("@", label),
    claimText = claim_text,
    caption = caption,
    sourceFile = "analysis.qmd",
    lineStart = bounds$start,
    lineEnd = bounds$end,
    reads = as.list(if (length(reads)) paste0("data/raw/", reads) else list()),
    writes = as.list(if (length(writes)) paste0("outputs/", writes) else list()),
    embeddedAsFigure = grepl("^fig-", label),
    githubPermalink = sprintf(
      "https://github.com/%s/blob/%s/analysis.qmd#L%d-L%d",
      github_repo, git_ref, bounds$start, bounds$end
    )
  )
}

manifest <- list(
  paper = list(
    doi = "10.1016/j.fishres.2025.107420",
    repo = paste0("https://github.com/", github_repo)
  ),
  generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  gitRef = git_ref,
  claims = entries
)

jsonlite::write_json(manifest, file.path(repo_root, "evidence.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf("Wrote evidence.json with %d claims\n", length(entries)))
