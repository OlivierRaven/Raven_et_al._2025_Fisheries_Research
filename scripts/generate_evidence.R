# Generates evidence.json: a manifest linking every crossref-citable
# fig-/tbl- claim in index.qmd to the exact analysis.qmd chunk that
# produced it, the data it reads, and the outputs it writes.
#
# Join key: the Quarto cross-reference label (e.g. "tbl-rf") is the same
# string in both files, so no new annotation scheme is needed beyond
# what Quarto authors already write.
#
# Many claim chunks are thin display wrappers (e.g. `x |> knitr::kable()`)
# whose actual computation — and actual file reads/writes — happened in an
# earlier, unlabelled chunk. This script traces backward through variable
# assignments to find that source and folds its lineage in too, recording
# which chunk(s) it came from as `computedIn` rather than silently merging
# with no attribution.
#
# This is a heuristic, not a real R data-flow analysis: it only follows
# bare top-level `var <- ...` assignments and whole-word variable mentions.
# Variables built inside loops with dynamic paths (e.g. read.delim(file_path)
# in a loop) aren't traceable this way and are a known gap.
#
# Run this after a successful `quarto render` — generatedAt is treated
# downstream as "last verified reproducible".

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

# ---- parse every ```{r}...``` chunk in the file, labelled or not ----
chunk_starts <- grep('^```\\{r', analysis_lines)
chunks <- list()
for (s in chunk_starts) {
  e <- s
  while (e < length(analysis_lines) && analysis_lines[e] != "```") e <- e + 1
  body <- paste(analysis_lines[s:e], collapse = "\n")
  label_match <- regmatches(body, regexpr('#\\|\\s*label:\\s*[^\n]+', body))
  label <- if (length(label_match)) trimws(sub('#\\|\\s*label:\\s*', "", label_match)) else NA_character_
  # Only `<-` counts as a real top-level assignment. A bare `=` at the start
  # of a trimmed line is just as often a named function argument written on
  # its own line inside a multi-line pipe (e.g. `mutate(\n  Year = as.factor(Year)\n)`)
  # as a real assignment, and this codebase consistently uses `<-` for the
  # latter — including `=` here produced false "variable" matches like
  # "data", "rownames", "tbl" that are really just argument names.
  own_vars <- character(0)
  for (ln in analysis_lines[s:e]) {
    m <- regmatches(ln, regexpr('^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*<-', ln, perl = TRUE))
    if (length(m) && nzchar(m)) {
      v <- sub('^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*<-.*', "\\1", m, perl = TRUE)
      own_vars <- c(own_vars, v)
    }
  }
  chunks[[length(chunks) + 1]] <- list(
    start = s, end = e, body = body, label = label, own_vars = unique(own_vars)
  )
}

# ---- global variable -> defining chunk index map (in file order) ----
var_defs <- new.env()
for (i in seq_along(chunks)) {
  for (v in chunks[[i]]$own_vars) {
    var_defs[[v]] <- c(get0(v, envir = var_defs, ifnotfound = integer(0), inherits = FALSE), i)
  }
}

chunk_index_at_line <- function(line) {
  for (i in seq_along(chunks)) {
    if (line >= chunks[[i]]$start && line <= chunks[[i]]$end) return(i)
  }
  NA_integer_
}

find_files <- function(body, fn_pattern, ext_pattern) {
  m <- gregexpr(paste0(fn_pattern, '\\(\\s*"([^"]+', ext_pattern, ')"'), body, perl = TRUE)
  matches <- regmatches(body, m)[[1]]
  unique(gsub(paste0('.*"([^"]+', ext_pattern, ')".*'), "\\1", matches))
}

find_reads <- function(body) {
  reads <- unique(c(
    find_files(body, "read_excel", "\\.xlsx"),
    find_files(body, "read\\.csv|read_csv", "\\.csv"),
    find_files(body, "readRDS", "\\.rds")
  ))
  reads[!is.na(reads)]
}

find_writes <- function(body) {
  writes <- unique(regmatches(
    body,
    gregexpr('file\\.path\\(out_dir,\\s*"\\s*([^"]+\\.(csv|png|rds))"\\)', body, perl = TRUE)
  )[[1]])
  out_writes <- if (length(writes) == 0) character(0) else
    # paste0("outputs/", character(0)) returns "outputs/" (length 1), not
    # character(0) — R treats a zero-length arg as "" for recycling here,
    # not as "propagate the empty vector" — hence the length check above.
    paste0("outputs/", trimws(gsub('file\\.path\\(out_dir,\\s*"\\s*([^"]+)"\\)', "\\1", writes)))

  # saveRDS(list(...), "literal/path.rds") — the path is a full literal
  # string, not built from out_dir, and is the LAST argument in a call that
  # usually spans many lines (one list element per line). [\\s\\S]*? matches
  # across those newlines non-greedily so this doesn't stop at the list's
  # own closing paren before reaching saveRDS's.
  rds_matches <- regmatches(
    body,
    gregexpr('saveRDS\\([\\s\\S]*?"([^"]+\\.rds)"\\s*\\)', body, perl = TRUE)
  )[[1]]
  direct_writes <- if (length(rds_matches) == 0) character(0) else
    # (?s) makes `.` match newlines too — these matches span many lines
    unique(gsub('(?s).*"([^"]+\\.rds)"\\s*\\)$', "\\1", rds_matches, perl = TRUE))

  unique(c(out_writes, direct_writes))
}

get_opt <- function(body, name) {
  m <- regmatches(body, regexpr(paste0('#\\|\\s*', name, ':\\s*"([^"]*)"'), body))
  if (length(m) == 0 || m == "") return(NA_character_)
  sub(paste0('#\\|\\s*', name, ':\\s*"([^"]*)"'), "\\1", m)
}

# Strips the ```{r}/``` fences and #| chunk-option lines, leaving just the
# real R code — this is what gets shown inline for the "interesting"
# ancestor chunks, so it shouldn't include Quarto's own bookkeeping.
strip_code <- function(body) {
  lines <- strsplit(body, "\n")[[1]]
  lines <- lines[!grepl("^```", lines)]
  lines <- lines[!grepl("^#\\|", lines)]
  while (length(lines) && !nzchar(trimws(lines[1]))) lines <- lines[-1]
  while (length(lines) && !nzchar(trimws(lines[length(lines)]))) lines <- lines[-length(lines)]
  paste(lines, collapse = "\n")
}

# Backward-traces ONE field (reads or writes) when a chunk has none of its
# own — e.g. a display-only chunk that just pipes an earlier variable into
# knitr::kable(). Kept as two independent chases (see resolve_lineage())
# rather than one combined pass: a chunk can have its own correct writes
# but no reads of its own (or vice versa), and merging both fields off a
# single "has either" check pollutes the field that was already complete
# with unrelated ancestors' files.
resolve_field <- function(chunk_idx, extractor, visited = integer(0)) {
  if (chunk_idx %in% visited) return(list(values = character(0), contributed = list()))
  visited <- c(visited, chunk_idx)
  ch <- chunks[[chunk_idx]]
  values <- extractor(ch$body)
  contributed <- list()

  if (length(values) == 0) {
    all_vars <- ls(var_defs)
    candidates <- all_vars[
      !(all_vars %in% ch$own_vars) &
      vapply(all_vars, function(v) grepl(paste0("\\b", v, "\\b"), ch$body, perl = TRUE), logical(1))
    ]
    src_idxs <- integer(0)
    for (v in candidates) {
      defs <- var_defs[[v]]
      earlier <- defs[defs < chunk_idx]
      if (length(earlier)) src_idxs <- c(src_idxs, max(earlier))
    }
    src_idxs <- unique(src_idxs)
    for (si in src_idxs) {
      sub <- resolve_field(si, extractor, visited)
      if (length(sub$values)) {
        values <- union(values, sub$values)
        contributed <- c(contributed, list(list(
          chunkIdx = si, label = chunks[[si]]$label,
          lineStart = chunks[[si]]$start, lineEnd = chunks[[si]]$end
        )))
      }
      contributed <- c(contributed, sub$contributed)
    }
  }

  list(values = values, contributed = contributed)
}

resolve_lineage <- function(chunk_idx) {
  reads_res <- resolve_field(chunk_idx, find_reads)
  writes_res <- resolve_field(chunk_idx, find_writes)
  list(
    reads = reads_res$values,
    writes = writes_res$values,
    contributed = c(reads_res$contributed, writes_res$contributed)
  )
}

# ---- build one entry per fig-/tbl- label actually surfaced in index.qmd ----
entries <- list()

for (chunk_idx in seq_along(chunks)) {
  label <- chunks[[chunk_idx]]$label
  if (is.na(label) || !grepl("^(fig|tbl)-", label)) next

  bounds <- list(start = chunks[[chunk_idx]]$start, end = chunks[[chunk_idx]]$end)
  body <- chunks[[chunk_idx]]$body

  tbl_cap <- get_opt(body, "tbl-cap")
  fig_cap <- get_opt(body, "fig-cap")
  caption <- if (!is.na(tbl_cap)) tbl_cap else fig_cap

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

  lineage <- resolve_lineage(chunk_idx)
  # Dedup by chunk, then sort chronologically (file order) rather than
  # discovery order, so this reads like the actual pipeline: raw data in,
  # cleaned, then analysed — not whatever order the backward chase visited
  # chunks in.
  seen_idx <- integer(0)
  contrib_idxs <- integer(0)
  for (contrib in lineage$contributed) {
    if (contrib$chunkIdx %in% seen_idx) next
    seen_idx <- c(seen_idx, contrib$chunkIdx)
    contrib_idxs <- c(contrib_idxs, contrib$chunkIdx)
  }
  contrib_idxs <- sort(contrib_idxs)

  entries[[length(entries) + 1]] <- list(
    label = label,
    manuscriptRef = paste0("@", label),
    claimText = claim_text,
    caption = caption,
    sourceFile = "analysis.qmd",
    lineStart = bounds$start,
    lineEnd = bounds$end,
    reads = as.list(lineage$reads),
    writes = as.list(lineage$writes),
    code = strip_code(body),  # this chunk's own code — shown even when it IS the interesting part (e.g. tbl-rf's own randomForest() call), not just when an ancestor did the real work
    contribIdxs = contrib_idxs,  # resolved into dataPipeline/computedIn below, once every claim is known
    embeddedAsFigure = grepl("^fig-", label),
    githubPermalink = sprintf(
      "https://github.com/%s/blob/%s/analysis.qmd#L%d-L%d",
      github_repo, git_ref, bounds$start, bounds$end
    )
  )
}

# ---- classify contributing chunks as shared pipeline vs claim-specific ----
# A chunk that shows up as an ancestor of most claims (in practice: raw data
# load -> clean -> cache) is boilerplate every claim depends on and isn't
# what makes THIS claim's number what it is — collapse those into one line
# with no code. A chunk that's an ancestor of only some claims (the actual
# model/statistical test) is the interesting part and gets its code shown.
all_contrib_idxs <- unique(unlist(lapply(entries, function(e) e$contribIdxs)))
pipeline_idxs <- integer(0)
if (length(entries) >= 2) {
  presence_count <- vapply(all_contrib_idxs, function(idx) {
    sum(vapply(entries, function(e) idx %in% e$contribIdxs, logical(1)))
  }, integer(1))
  pipeline_idxs <- all_contrib_idxs[presence_count > length(entries) / 2]
}

chunk_ref <- function(idx, with_code) {
  ch <- chunks[[idx]]
  base <- list(
    label = ch$label,
    lineStart = ch$start,
    lineEnd = ch$end,
    githubPermalink = sprintf(
      "https://github.com/%s/blob/%s/analysis.qmd#L%d-L%d",
      github_repo, git_ref, ch$start, ch$end
    )
  )
  if (with_code) base$code <- strip_code(ch$body)
  base
}

for (i in seq_along(entries)) {
  idxs <- entries[[i]]$contribIdxs
  pipeline <- idxs[idxs %in% pipeline_idxs]
  interesting <- idxs[!(idxs %in% pipeline_idxs)]
  entries[[i]]$contribIdxs <- NULL
  entries[[i]]$dataPipeline <- lapply(pipeline, chunk_ref, with_code = FALSE)
  entries[[i]]$computedIn <- lapply(interesting, chunk_ref, with_code = TRUE)
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
