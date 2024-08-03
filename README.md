# `dom-persist`

This is a simple way of storing a DOM, either HTML or XML, into the Sqlite database using the D programming language.
It provides a way to cache all DOM edits in RAM and only persist to the database when flush is called. This provides
excellent performance and flexibility. DB storage is also at the element granularity providing indexing by ID.
