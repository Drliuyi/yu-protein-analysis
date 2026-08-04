# Yu/Chen 2025 code-availability audit

## Article identity

- Title: *Systematic analyses uncover plasma proteins linked to incident cardiovascular diseases*
- Journal: *Protein & Cell*
- DOI: `10.1093/procel/pwaf072`
- PMID: `40927895`
- PMCID: `PMC12987571`
- Advance publication: 2025-08-06

## Search result

Searches were performed using the exact title, DOI, article code `pwaf072`, and
author combinations in web search and the GitHub repository API. No author
analysis repository, archived source-code bundle, or executable notebook was
identified.

The article's `Code availability` statement lists public software and versions,
but does not link to author scripts or a repository. Consequently, this project
is an independent, source-locked implementation. It must not be described as a
line-for-line reproduction of unpublished author code.

## Available primary materials

1. Full article text from Oxford Academic / PubMed Central.
2. Supplementary methods and Figures S1-S5 PDF.
3. Supplementary workbook containing Tables S1-S26.
4. Main-figure raster images from the PubMed Central open-access package.
5. Public software named by the authors: `survival 3.5.5`, `lightgbm 3.3.2`,
   `TwoSampleMR 0.5.8`, `PLINK 2.0`, `PRSice 1.25`, `CMAverse 0.1.0`,
   `Cytoscape 3.10.0`, STRING, Metascape, MGI, and TRRUST.

## Reproducibility limits in the publication

- The participant-level derivation/test EIDs and random seed were not released.
- The exact LightGBM tuning search space was not released; only the final
  hyperparameters were reported.
- The preliminary LightGBM seed and tie handling for cumulative 30% importance
  selection were not reported.
- The classification threshold used for accuracy, sensitivity, specificity,
  and F1 was not reported.
- Figure 4 describes bootstrap error bars as IQR, whereas the supplementary
  methods describe median and 95% confidence intervals. This implementation
  exports both.
- SCORE2 isotonic recalibration details beyond the method name were not
  released.
- External web-tool sessions for Metascape, STRING, MGI, and TRRUST were not
  archived.

All local decisions for these unresolved items are recorded in
`config/method_provenance.csv` and must be frozen before formal execution.

