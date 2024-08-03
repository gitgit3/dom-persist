### `dom-persist`

This is a simple way of storing a DOM, either HTML or XML, into the Sqlite database using the D programming language.
It provides a way to cache all DOM edits in RAM and only persist to the database when flush is called. This provides
excellent performance and flexibility. DB storage is also at the element granularity providing indexing by ID.

### `Usage`

```
import dom_persist;
import nodecode;

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

//create some nodes

tree_node.appendChild( TreeNodeType.docType, "html" );
auto tn_html = tree_node.appendChild( TreeNodeType.element, "html" );

auto tn_head = tn_html.appendChild( TreeNodeType.element, "head" );
tn_head.appendChild( TreeNodeType.comment, "This is my comment" );

auto tn_body = tn_html.appendChild( TreeNodeType.element, "body" );

tn_body.appendChild( TreeNodeType.text, "This is some text" );
tn_body.appendChild( TreeNodeType.text, " with more text" );
tn_body.appendChild( TreeNodeType.element, "input" );

// write changes to DB
tree.flush();

// get the html as a text string
string html_out = tree.getTreeAsText( );	
writeln( html_out );


```
