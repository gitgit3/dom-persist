### `dom-persist`

This is a simple way of storing a DOM, either HTML or XML, into the Sqlite database using the D programming language.
It provides a way to cache all DOM edits in RAM and only persist to the database when flush is called. This provides
excellent performance and flexibility. DB storage is also at the element granularity providing indexing by ID.

### `Usage`

```
string sqlite_filename = "dom_persist_test.db";
if(!db_exists( sqlite_filename ) {
  //create database
  Database db = db_create( sqlite_filename, 1 );
  //create schema
  Tree_Db.db_create_schema( db );
}

// create a DOM tree
Tree_Db tree = Tree_Db.createTree( db, "mytree" );

// get the tree (root) node 
TreeNode tree_node = tree.getTreeRoot();


```
