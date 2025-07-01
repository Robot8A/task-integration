# task-integration

**Article Title:**  
*Identifying Potential Quality Issues Derived From Collective Intelligence in Humanitarian Mapping: Microtask Aggregation in the HOT Tasking Manager*

---

This repository contains the code and data associated with the article. It includes:

- Scripts for data collection and processing  
- Jupyter Notebooks used for analysis  
- The primary dataset (incident counts and computed quality indicators at the project level)  
- Supplementary materials (e.g., project heatmaps used in the manual review of Geary’s C values)

---

## Reproducibility of Figures and Tables

### Section 5.2 – Edge-based Issues

This section includes **Figures 6 and 7**, and **Table 1**. Each item is divided into two parts:
- **Left side**: Results for **large building intersections**
- **Right side**: Results for **road terminations**

**Relevant notebooks:**
* [View `Large_building_intersections.ipynb`](https://github.com/Robot8A/task-integration/blob/main/Data%20Analysis/Large_building_intersections.ipynb)  
* [View `Road_terminations.ipynb`](https://github.com/Robot8A/task-integration/blob/main/Data%20Analysis/Road_terminations.ipynb)


#### Figure 6. Comparison of the proportion of nodes per project (%) in selected edge areas (5%, 10%, 15%) vs. equivalent random areas. Significant differences with respect to expected values at p < 0.05*, p < 0.01**, and p < 0.001***.  
![Comparison of the proportion of nodes per project (%) in selected edge areas (5%, 10%, 15%) vs. equivalent random areas. Significant differences with respect to expected values at p < 0.05*, p < 0.01**, and p < 0.001***.](https://github.com/Robot8A/task-integration/raw/main/images/edgeeffect.jpg)

Displays the proportion of nodes per project located in selected edge areas (5%, 10%, 15%) compared to random areas.

Each subfigure includes:
- A top table with descriptive statistics  
- Bottom boxplots  
- Statistical test results

**Implementation details:**  
See section `1. Characterization of areas: edge and random (5%, 10%, 15%)` in the corresponding notebook.

#### Figure 7. Mean difference between the observed and expected proportion of nodes (’Difference’) and its rate of change (’Change’) as a function of edge area.  
![Mean difference between the observed and expected proportion of nodes (’Difference’) and its rate of change (’Change’) as a function of edge area.](https://github.com/Robot8A/task-integration/raw/main/images/borderprofile.jpg)

Explores how the average percentage of event occurrences changes across concentric ring areas along the task boundary (in 5% increments up to full coverage).

- **Top plots**:  
  - Line: difference between observed and expected occurrences  
  - Bars: incremental change in that difference  
- **Bottom plots**:  
  - Heatmaps preserving square task geometry

**Implementation details:**  
See section `2. Profiling the difference between the observed and expected proportion of nodes (‘Difference’) and its rate of change (‘Change’) as a function of edge area at 5% increments`.

#### Table 1. Regression analysis of the edge effect (Significant regressors at p < 0.05 are highlighted) 
![Regression analysis of the edge effect (Significant regressors at p < 0.05 are highlighted)](https://github.com/Robot8A/task-integration/raw/main/images/regressionedgeeffect.jpg)

Presents results of a regression analysis examining how project characteristics affect the difference between observed and expected event concentrations at task boundaries. Includes:

- Independent variables  
- Regression coefficients  
- Standard errors  
- t-statistics  
- p-values

**Implementation details:**  
See section `3. Regression analysis of the edge effect (diff)`.

---

### Section 5.3 – Task-wide Issues

This section includes **Figures 8 and 9**, and **Table 2**.

**Relevant notebook:**
- [View `GearyAnalysis.ipynb`](https://github.com/Robot8A/task-integration/blob/main/Data%20Analysis/GearyAnalysis.ipynb)

#### Figure 8. Geary’s C distribution (n=2,972).  
![Geary’s C distribution (n=2,972)](https://github.com/Robot8A/task-integration/raw/main/images/GearyDistribution.png)

Combines a boxplot and violin plot to show the distribution of valid Geary’s C values across projects.

**Implementation details:**  
See section `2. Describe Geary’s C`.

#### Figure 9. Geary’s C Profiling (n=4,274). 
![Geary’s C Profiling (n=4,274)](https://github.com/Robot8A/task-integration/raw/main/images/GearyProfiling.jpg)

Presents profiles of different project categories based on their Geary’s C values. Displays average z-scores (standardized values) for:

- Number of tasks (`Tasks`)  
- Total number of contributors (`Contributors`)  
- Building density (`Buildings/Area`)  
- Average area per task (`Area/Tasks`)

**Implementation details:**  
See section `3. Profiling projects per Geary’s C category`.


### Manual Inspection of Project Heatmaps
#### Table 2. Counting and characterizing the sample of projects exhibiting negative spatial autocorrelation (C > 1) according to whether different mapping styles are identified through inspection (n=78)
![Counting and characterizing the sample of projects exhibiting negative spatial autocorrelation (C > 1) according to whether different mapping styles are identified through inspection (n=78)](https://github.com/Robot8A/task-integration/raw/main/images/GearyTable.jpg)

The final table in Section 5.3 is based on the manual inspection of a sample of project heatmaps.

The list of these projects and their characteristics can be found in the spreadsheet [View `sampleGeary.xlsx`](https://github.com/Robot8A/task-integration/blob/main/Data%20Analysis/sampleGeary.xlsx). In this spreadsheet:

- The **"atlas"** column shows the project heatmap identifier, which can be found in the [View `Project heatmaps`](https://github.com/Robot8A/task-integration/blob/main/atlas/) folder.
- The **"Different style"** column identifies the category resulting from the manual inspection.

A second tab of the spreadsheet contains the medians of variables relevant to the identified project categories.

---




## Description
Prerequisites:
* Python 3 (tested with 3.11.2)
    * Install libraries via requirements.txt
* PostgreSQL (tested with 15.2)
    * PostGIS (tested with 3.3.2)


Run the files in numerical order according to their filename. Shell and Python scripts should be run on the terminal, SQL files inside the database.

Files with equal numbers but different letters can be run in parallel.

## License
[GPL-3.0 license](LICENSE)
