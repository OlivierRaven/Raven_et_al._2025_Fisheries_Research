# Assessment of spatial and temporal stability of tributary-specific otolith trace element signatures

O.V. Raven, J.E.M. Couper, H. Trotter, M.R. Reid, R. Svirgsden, M. Rohtla, G.P. Closs

**Published:** Fisheries Research 287 (2025) 107420
**Article DOI:** [10.1016/j.fishres.2025.107420](https://doi.org/10.1016/j.fishres.2025.107420)
**Code & data archive (Zenodo, concept DOI, always resolves to the latest version):** [10.5281/zenodo.21539667](https://doi.org/10.5281/zenodo.21539667)

## Overview

This repository contains the reproducible analysis workflow supporting the manuscript above: a four-year (2020–2023) study of 602 juvenile brown trout (*Salmo trutta*) otoliths from 20 tributaries of the lower Clutha River/Mata-Au, New Zealand, testing the spatial and temporal stability of otolith trace element signatures (Mn, Sr, Ba) for tracking natal-stream origin across generations.

**Key findings:**

- Mn, Sr, and Ba signatures were spatially variable but temporally stable across the four sampling years, meeting the criteria needed for inter-generational natal-origin tracking.
- A Random Forest model assigned juveniles to their correct stream 61–62% of the time; Linear Discriminant Analysis achieved 52–53%.
- Grouping sites into three geologically-associated clusters (Nearest-Neighbour Cluster Analysis) raised classification accuracy to ~93% for both models.
- Collection of juveniles across 2–3 years from key spawning tributaries should be sufficient to build reference signatures usable for tracking adult migration over several years.

## Repository structure

    .
    ├── data/
    │   ├── raw/           # Original field/lab data (Excel, slide exports)
    │   └── derived/       # Cleaned/processed data used in the analysis
    ├── outputs/           # Generated figures and tables
    ├── references/        # Bibliography (.bib), citation style, LaTeX header
    ├── scripts/           # Supporting scripts
    ├── images/            # Manuscript images
    ├── docs/              # Rendered HTML output (GitHub Pages)
    ├── _quarto.yml        # Quarto manuscript project configuration
    ├── analysis.qmd       # Full analysis notebook (data cleaning, MANOVA, RF/LDA models, figures)
    └── index.qmd          # Manuscript article

## Reproducing the analysis

This project uses [Quarto](https://quarto.org/) and R.

### Requirements

- R >= 4.3
- Quarto >= 1.4
- R packages: `here`, `gt`, `knitr`, `DT`, `palmerpenguins`, `caret`, `cluster`, `MASS`, `ggpubr`, `randomForest`, `patchwork`, `tidyverse`, `dplyr`, `ggplot2`, `readxl`, `writexl`, `readr`

### Install R packages

This project uses [`renv`](https://rstudio.github.io/renv/) to pin exact package versions. From the project root in R:

```r
install.packages("renv")
renv::restore()
```

### Render the analysis

```
quarto render analysis.qmd
quarto render index.qmd
```

The rendered site is published at: <https://olivierraven.github.io/Raven_et_al._2025_Fisheries_Research/>

## Data availability

Raw ablation data (`data/raw/`) and derived data (`data/derived/`) needed to reproduce the statistical analyses and figures are both tracked in this repository. As stated in the published article, the data underlying this study are available on request; this repository, and its permanent archive on Zenodo, provide open access to those same files and to the full analysis code.

Generated outputs (figures, tables, confusion matrices) are tracked in `outputs/`.

Each tagged release of this repository (starting with `v1.0-published`) is automatically archived on Zenodo with its own versioned DOI:

- **Concept DOI** (cite this for "the latest version"): [10.5281/zenodo.21539667](https://doi.org/10.5281/zenodo.21539667)
- **v1.0-published DOI** (cite this to reference the exact state at time of publication): [10.5281/zenodo.21539668](https://doi.org/10.5281/zenodo.21539668)

## Funding

This project was funded by Contact Energy Ltd and executed by the Otago Fish and Game Council in cooperation with the University of Otago, Department of Zoology.

## Citation

Raven, O.V., Couper, J.E.M., Trotter, H., Reid, M.R., Svirgsden, R., Rohtla, M., Closs, G.P., 2025. Assessment of spatial and temporal stability of tributary-specific otolith trace element signatures. Fisheries Research 287, 107420. <https://doi.org/10.1016/j.fishres.2025.107420>

## Licence

Code: MIT License
Data: CC BY 4.0 (as archived on Zenodo)
