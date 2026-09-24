# Verify that every relative markdown link resolves: the file it names must exist, and when it
# carries a #fragment, that fragment must match a real heading -- in another file or in this one.
#
# Both failures are silent. The link still renders, and only fails when a reader clicks it. The
# guides and the decision records cross-reference each other both ways, so one renamed heading or
# one moved file can break several files at once. A miscounted `../` is the easy one to miss,
# because the path looks plausible and no tool complains; that is how a dead link to the
# task-continuity skill survived in scripts/tests/continuity-fixtures/README.md.
#
# A link to <name>.md is satisfied by a <name>.md.tmpl source, because chezmoi renders the
# template to that name in the target. Headings inside a .tmpl are not verified: the staged
# snapshot holds the unrendered template, so its headings are not knowable here.
#
# Prints the number of links checked and exits 0 when they all resolve; prints the offenders
# and exits 1 when they do not.
#
# Fenced blocks are skipped on both sides: their "# comment" lines are not headings, and the
# links inside them are usually illustrative templates naming files that do not exist.

function normalise(dir, path,   parts, n, out, i, top, result) {
  n = split(dir "/" path, parts, "/")
  top = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (top > 0) top--; continue }
    out[++top] = parts[i]
  }
  result = ""
  for (i = 1; i <= top; i++) result = result (i > 1 ? "/" : "") out[i]
  return result
}

FNR == 1 { fence = ""; prev = ""; scanned[FILENAME] = 1 }  # state must not leak between files
/^[[:space:]]*(```|~~~)/ {
  marker = ($0 ~ /^[[:space:]]*```/) ? "`" : "~"
  if (fence == "") fence = marker                # opening: remember which character it was
  else if (fence == marker) fence = ""           # only the same character closes it
  next
}
fence != "" { next }

# A setext heading is the previous line underlined with = or -, so headings are registered one
# line late; only the slug matters, not the order.
/^[[:space:]]*(=+|-+)[[:space:]]*$/ && prev != "" { record(prev); prev = ""; next }
/^#{1,6}[[:space:]]/ {
  h = $0
  sub(/^#+[[:space:]]+/, "", h)
  record(h)
  prev = ""
  next
}
{ prev = $0 }

function record(h,   slug) {
  gsub(/\]\([^)]*\)/, "]", h)                   # a link in a heading contributes its text only;
  gsub(/[][]/, "", h)                           # awk gsub has no backreference, so do it in two
  gsub(/`|\*/, "", h)                           # code spans and emphasis do not reach the slug
  slug = tolower(h)
  gsub(/[^a-z0-9 _-]/, "", slug)                # underscores DO survive into a GitHub anchor
  gsub(/ /, "-", slug)
  # GitHub disambiguates a repeated heading by appending -1, -2, ... in document order.
  if ((FILENAME SUBSEP slug) in heading) {
    seen[FILENAME SUBSEP slug]++
    heading[FILENAME SUBSEP slug "-" seen[FILENAME SUBSEP slug]] = 1
  } else {
    heading[FILENAME SUBSEP slug] = 1
  }
}

{
  # Two forms: a relative link into another file, and a bare fragment inside this one.
  line = $0
  gsub(/`[^`]*`/, "", line)                     # a link inside a code span is being shown, not made
  gsub(/<!--.*-->/, "", line)                   # nor is one inside a comment
  # The character class excludes ":", so an absolute http(s) or mailto target never matches and
  # only repository-relative links are collected.
  while (match(line, /\]\([A-Za-z0-9._\/#-]+\)/)) {
    src[++total] = FILENAME
    raw[total] = substr(line, RSTART + 2, RLENGTH - 3)
    lno[total] = FNR
    line = substr(line, RSTART + RLENGTH)
  }
}

# One stat per distinct path: a link-heavy tree would otherwise fork test(1) hundreds of times.
function exists(path) {
  if (!(path in statted)) statted[path] = (system("test -e \"" path "\"") == 0)
  return statted[path]
}

END {
  for (i = 1; i <= total; i++) {
    n = split(raw[i], part, "#")
    if (part[1] == "") {
      target = src[i]                             # bare #fragment: same file
      rendered = 0
    } else {
      dir = src[i]
      if (!sub(/\/[^\/]*$/, "", dir)) dir = "."
      target = normalise(dir, part[1])
      # A markdown file with no lines never reaches FNR == 1, so confirm on disk before blaming
      # the path rather than the fragment.
      rendered = 0
      if (!(target in scanned) && !exists(target)) {
        if (!exists(target ".tmpl")) {
          printf "    %s:%d -> %s (no such file)\n", src[i], lno[i], raw[i], ""
          bad++
          continue
        }
        rendered = 1                              # exists only as the template that renders to it
      }
    }
    if (n < 2) continue                           # plain file link: existence was the whole check
    if (rendered) continue                        # headings of an unrendered template are unknowable
    if (target SUBSEP part[2] in heading) continue
    printf "    %s:%d -> %s (no such heading)\n", src[i], lno[i], raw[i]
    bad++
  }
  if (bad) exit 1
  print total
}
