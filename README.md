Summary:
Leadership has expressed an interest in getting a better summary of our usage data in our system. The existing data structures are old, and you’ll need to get them the information while identifying a path forward to make the data clean, reliable and useful.

NOTE: Any technology can be used for each of these steps. 

Fork this repo

In your fork, do the following:

- Create a simple line chart showing Total Usage (MB) per day.
- Answer the following questions:
    - Which `sim_card_id` had the highest total usage?  1 if you remove duplicates.  2 if you keep the duplicates
    - How many usage events resolved to 3G after any cleanup is finished?  I found 2.
    - How many duplicate usage events did you identify?  sid 2 has 3 records.   2 appear to be duplicates and 1 has a higher mb.
    - What is the cost of all data used in the linked data?
- Include code, queries, and brief documentation needed to reproduce your work
    - If any frameworks, libraries, or other tools are needed, include them in your documentation.
- Review the provided ERD and describe how you would redesign the database to make the data cleaner, more reliable and useful. 
    I redesigned this as a star schema.  More  work needs to go into this since I don't have clear definitions of the ids.  Realistically, all the ids would have a description.  For example if cc1 is a stateand cc2 is a country, I would include the two digit state codes and full name of the state.  For the country, I would include both the 2 and 3 digit country codes and the full names.
    
    - What are some risks and tradeoffs with this redesign.
         This is an OLAP model so if may require batch processing and the data would not be in real time.  However, you could set this up as a streaming model with micro-batching.  It all depends on the use case.  Real time stream will require more compute and be more  expensive.
      
    - Include any model considerations, such as keys, constraints, and indices.
    - This can be done as any of the following:
        - A new ERD (if this route, flag constraints/indices somehow).  A lot of these considerations,require follow up questions.  For example, the partitioning is not necessary if the table is not over 1 TB.  For indexing, this depends on how the users are  looking up the data.  If you are using Databricks, liquid clustering is ideal since it keeps your partitons even.  You can use this to index up to 4 columns.  Furthermore, if  you setup predictive optimiations in Databricks, a lot of features like Vaccuum and optimize are setup automatically
        - A list of SQL statements building the new models.  See SQL file.
        - A detailed summary of the changes you would make.
- Document
    - Any Data Quality problems, and how you resolved them
    - Any Questions you might ask about the existing data to clarify your assumptions
    - Assumptions - NOTE: there isn’t necessarily a “one size fits all” answer. We want to see your reasoning.

The new ERD, answers, and chart should all be included in the base folder of the forked repo.
When complete, send a link to your repo to your interviewer.
