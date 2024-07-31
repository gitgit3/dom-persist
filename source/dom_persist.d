module dom_persist;

import std.file;
import std.conv;
import std.stdio;
import std.format;
import std.exception : enforce;
import std.traits;


import d2sqlite3;	// https://d2sqlite3.dpldocs.info/v1.0.0/d2sqlite3.database.Database.this.html

version(unittest){	
	//stuff only compiled for unittests
	string sqlite_filename = "dom_persist_test.db";
}

unittest {
		
	db_drop( sqlite_filename );
	assert( !db_exists( sqlite_filename ) );

	Database db = db_create( sqlite_filename, 1 );

	assert( db_exists( sqlite_filename ) );	
	assert(db.tableColumnMetadata("params", "ID") == TableColumnMetadata("INTEGER", "BINARY", false, true, true));

	Tree_Db_Base tdb = new Tree_Db_Base( db );
	tdb.db_create_schema( );
	
	assert(db.tableColumnMetadata("doctree", "ID") == TableColumnMetadata("INTEGER", "BINARY", false, true, true));
	
	long tree_id = tdb.create_tree("mytree");
	
	long nid = tdb.appendChild( tree_id, tree_id, TreeNodeType.docType, "html" );
	long html_nid = tdb.appendChild( tree_id, tree_id, TreeNodeType.element, "html" );
	
	long head_id = tdb.appendChild( tree_id, html_nid, TreeNodeType.element, "head" );
	tdb.appendChild( tree_id, head_id, TreeNodeType.comment, "This is my comment" );
	
	long body_id = tdb.appendChild( tree_id, html_nid, TreeNodeType.element, "body" );
	tdb.appendChild( tree_id, body_id, TreeNodeType.text, "This is some text" );
	tdb.appendChild( tree_id, body_id, TreeNodeType.text, " with more text" );
	tdb.appendChildElement( tree_id, body_id, "input" );
	
	string html_out = tdb.getTreeAsText( tree_id );	
	//writeln( html_out );
	assert( html_out == "<DOCTYPE html><html><head><!--This is my comment--></head><body>This is some text with more text<input/></body></html>");
	
	db.close();
}

bool db_exists( string sqlite_filename ){
	return sqlite_filename.exists;
}

void db_drop( string sqlite_filename ){
	if( sqlite_filename.exists ){
		sqlite_filename.remove();
	}	
}

Database db_create( string sqlite_filename, int db_ver ){
	
	auto db = Database( sqlite_filename );
	db.run("CREATE TABLE \"Params\"(\"ID\" INTEGER, \"Name\"	TEXT NOT NULL UNIQUE, \"Val\"	TEXT,	PRIMARY KEY(\"ID\" AUTOINCREMENT))");
	db.run("Insert into params(Name, Val) values('DB_VERSION','"~to!string(db_ver)~"')");
	return db;
}

enum TreeNodeType {
	nulltype=-2, // indicates a type read from the database which is not one of the recognised types
	tree=-1, docType, element, text, comment
}

TreeNodeType getTreeNodeType( int tip ){
	
	auto tnts = [EnumMembers!TreeNodeType];
	foreach( tnt; tnts ){
		if( tnt==tip ) return tnt;
	}
	return TreeNodeType.nulltype;
}


struct NodeData {
	
	long ID;
	string e_data;
	long pid;
	TreeNodeType type;
	
	this( long ID, string e_data, long pid, TreeNodeType type){
		this.ID = ID;
		this.e_data = e_data;
		this.pid = pid;
		this.type = type;
	}
}

/**
 * This class provides direct database access to all trees in the database table. You can also obtain from it
 * an instance of class Tree_Dd for a specific tree given its root node id.
 */
class Tree_Db_Base {
	
	protected:
		Database* db;
		static long node_count = 0;
		
	public:
	
	this( ref Database db ){
		this.db = &db;
	}
	
	/**
	 * Create a new tree in the tree table and return the ID of the tree node. Note that the tree node is
	 * the parent of the root node, doctype and maybe other node data.
	 * 
	 * The tree node is marked with '0' (zero) since it has no parent.
	 */
	long create_tree( string tree_name ){		
		return appendChild( 0, 0, TreeNodeType.tree, tree_name);
	}
	
	/**
	 * Read the DOM from this database for the given tree ID (tid) and return as
	 * an html (or xml) string.
	 * 
	 * Note that the tree node (type==0) does not have a string representation.
	 */
	string getTreeAsText( long tid ){
		//NodeData cTree = getChild( tid );	//we don't want to print the 'tree' node
		return getTreeAsText_r( tid );
	}
	
	string getTreeAsText_r( long tid ){
		
		string strRtn = "";

		NodeData[] children = getChildren( tid );
		foreach( child; children){
			strRtn ~= get_openTag_commence( child.type, child.e_data );
			// --> add attributes if required
			strRtn ~= get_openTag_end( child.type, child.e_data );
			strRtn ~= getTreeAsText_r( child.ID );
			strRtn ~= get_closeTag( child.type, child.e_data );
		}
		
		return strRtn;
	}
	
	/**
	 * Return the (ordered) child node IDs of the given parent_id.
	 */
	NodeData[] getChildren( long parent_id ){
	
		NodeData[] child_nodes;
		auto results = db.execute( format("select ID, e_data, p_id, t_id from doctree where p_id=%d", parent_id) );
		foreach (row; results){
			
			//assert(row.length == 3);
			
			child_nodes ~= NodeData( 
				row.peek!long(0),
				row.peek!string(1),
				row.peek!long(2),
				getTreeNodeType( row.peek!int(3) )
			);
			
		}
		return child_nodes;
	}

	NodeData getChild( long cid ){

		auto results = db.execute( format("select ID, e_data, p_id, t_id from doctree where id=%d", cid) );
		foreach (row; results){
			
			//assert(row.length == 1);
			
			return NodeData( 
				row.peek!long(0),
				row.peek!string(1),
				row.peek!long(2),
				getTreeNodeType( row.peek!int(3) )
			);
			
		}
		throw new Exception( format( "Child with ID(%d) not found", cid) );

	}

	/**
	 * Append a new element to the given parent id (pid)
	 */
	long appendChildElement( long tree_id, long pid, string elem_name ){
		enforce(elem_name!=null && elem_name.length>0 );
		return appendChild( tree_id, pid, TreeNodeType.element, elem_name );
	}

	/**
	 * Append new text to the given parent id (pid).
	 * Returns the ID of the text node if appended or -1 otherwise.
	 */
	long appendChildText( long tree_id, long pid, string text ){
		if(text==null || text.length==0 ) return -1;
		return appendChild( tree_id, pid, TreeNodeType.text, text );
	}

	/**
	 * Append new text to the given parent id (pid).
	 * Returns the ID of the text node if appended or -1 otherwise.
	 */
	long appendChildComment( long tree_id, long pid, string text ){
		if(text==null || text.length==0 ) return -1;
		return appendChild( tree_id, pid, TreeNodeType.comment, text );
	}

	/**
	 * Append a new node to the given parent pid.
	 * node_data is used only for doctype, element and text
	 * 
	 * The ID of the new node is returned.
	 */
	long appendChild( long tree_id, long pid, TreeNodeType nt, string node_data = "" ){
		
		if( nt == TreeNodeType.docType ){
			//we might store the extra data as an attribute but this will suffice for the moment
			node_data = "DOCTYPE "~node_data;
		}
		db.run( format("Insert into doctree(e_data, p_id, t_id, tree_id, c_odr ) values( '%s', %d, %d, %d, %d )", node_data, pid, nt, tree_id, node_count ) );
		node_count+=1;
		return db.lastInsertRowid;		
	}

	/**
	 * Close this object AND the underlying DB connection.
	 */
	void close(){
		db.close();
		db=null;
	}
	
	void db_create_schema( ){		
		db.run("CREATE TABLE IF NOT EXISTS doctree (ID INTEGER, e_data	TEXT,p_id INTEGER,t_id INTEGER NOT NULL,tree_id INTEGER NOT NULL,	c_odr INTEGER NOT NULL, PRIMARY KEY( ID AUTOINCREMENT))");
	}
	
	long getRootId(){
		return -1;
	}
	
}

string get_openTag_commence( TreeNodeType nt, string e_data ){
	
	switch( nt ){
	
	case TreeNodeType.text:
		return e_data;
		
	case TreeNodeType.comment:
		return "<!--"~e_data;
		
	default:
		return "<"~e_data;
	}
}

string get_openTag_end( TreeNodeType nt, string e_data ){

	switch( nt ){
		
	case TreeNodeType.comment:
	case TreeNodeType.text:
		return "";
			
	default:
		switch(e_data){
		case "input":
		case "br":
			return "/>";
		default:
		}
		
		return ">";
	}
	
}

string get_closeTag( TreeNodeType nt, string e_data ){

	switch( nt ){
		
	case TreeNodeType.docType:
	case TreeNodeType.text:
		return "";
		
	case TreeNodeType.comment:
		return "-->";
		
	default:
		switch(e_data){
		case "input":
		case "br":
			return "";
		default:
		}

		return format("</%s>", e_data);
	}
	
}


struct TreeNameID {
	long tree_id;
	string name;
}

struct TreeNode {
	NodeData node_data;
	TreeNode*[] child_nodes;
}

/**
 * An instance of this class contains access to a single tree. Tree operations are cached in RAM and only written to
 * disk during a save operation. This can be done safely because of the single user access to Sqlite.
 * 
 * Multiple database connections should work on the same thread provided each is using a different tree.
 * 
 * Instantiation of the tree involves only one database select.
 */
class Tree_Db {

	protected:
	
		long tree_id;
		Database* db;		
		
		TreeNode[long]	all_nodes;
		
		
	this( Database db, long tid ){

		this.db = &db;
		tree_id = tid;

		//load the tree in one hit using the tree_id
		//also order by the parent_id so that we know all siblings are grouped together
		//and also by child order

		auto results = db.execute( format("select ID, e_data, p_id, t_id from doctree where tree_id=%d or id=%d order by p_id,c_odr", tree_id, tree_id) );
		foreach (row; results){
			
			long id = row.peek!long(0);
			long p_id = row.peek!long(2);
			TreeNode tn;
			tn.node_data = NodeData(
				id,
				row.peek!string(1),
				p_id,
				getTreeNodeType( row.peek!int(3) )
			);
			all_nodes[id] = tn;
			if(p_id==0) continue;
			all_nodes[p_id].child_nodes ~= &all_nodes[id];
		}

	}
	
	public:
	
	/**
	 * Return a list of all trees in the database with their ID's and names.
	 */
	static TreeNameID[] getTreeList( ref Database db ){

		TreeNameID[] tree_list;
		auto results = db.execute( format("select ID, e_data from doctree where p_id=0") );
		foreach (row; results){
			
			tree_list ~= TreeNameID (
				row.peek!long(0),
				row.peek!string(1)
			);			
		}
		return tree_list;		
	}
	
	static Tree_Db loadTree( ref Database db, long tid ){
		return new Tree_Db( db, tid );
	}
	
	TreeNode getTreeNode(){
		return all_nodes[tree_id];
	}
	
}

unittest{

	auto db = Database( sqlite_filename );
		
	TreeNameID[] tree_list = Tree_Db.getTreeList( db );
	assert( tree_list.length==1 );
	
	Tree_Db tree = Tree_Db.loadTree( db, tree_list[0].tree_id );
	
	TreeNode tree_node = tree.getTreeNode();
	NodeData nd_t = tree_node.node_data;
	assert( nd_t.ID == tree_list[0].tree_id );
	assert( nd_t.e_data == tree_list[0].name );
	assert( nd_t.pid == 0 );
	assert( nd_t.type == TreeNodeType.tree );
	
	//writeln( tree_node.child_nodes );
	
	int i=0;
	foreach( node_ptr; tree_node.child_nodes ){		

		NodeData c_node = (*node_ptr).node_data;
		
		switch(i){
		case 0:
			assert( c_node.ID == 2 );
			assert( c_node.e_data == "DOCTYPE html" );
			assert( c_node.pid == tree_list[0].tree_id );
			assert( c_node.type == TreeNodeType.docType );
			break;

		case 1:
			assert( c_node.ID == 3 );
			assert( c_node.e_data == "html" );
			assert( c_node.pid == tree_list[0].tree_id );
			assert( c_node.type == TreeNodeType.element );
			break;
		
		default:
		}
	
		//writeln( c_node );
		i+=1;
	}
	
	
	
}
