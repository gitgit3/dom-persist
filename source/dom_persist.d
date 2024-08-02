module dom_persist;

import std.file;
import std.array;	//https://dlang.org/phobos/std_array.html
//import std.algorithm; //https://dlang.org/phobos/std_algorithm_mutation.html
import std.conv;
import std.stdio;
import std.format;
import std.exception : enforce;
import std.traits;


import d2sqlite3;	// https://d2sqlite3.dpldocs.info/v1.0.0/d2sqlite3.database.Database.this.html
						// https://dlang-community.github.io/d2sqlite3/d2sqlite3.html

version(unittest){	

	//stuff only compiled for unittests
	string sqlite_filename = "dom_persist_test.db";

	void assertNDRecord( Row row, long id, string e_data, long pid, TreeNodeType tnt ){
	
		assert( id == row.peek!long(0) );
		assert( e_data == row.peek!string(1) );
		assert( pid == row.peek!long(2) );
		assert( tnt == getTreeNodeType( row.peek!int(3) ) );
	
	}
}

unittest {
	
	writeln( "Testing tree creation" );
	
	db_drop( sqlite_filename );
	assert( !db_exists( sqlite_filename ) );

	Database db = db_create( sqlite_filename, 1 );

	assert( db_exists( sqlite_filename ) );	
	assert(db.tableColumnMetadata("params", "ID") == TableColumnMetadata("INTEGER", "BINARY", false, true, true));

	Tree_Db.db_create_schema( db );
	assert(db.tableColumnMetadata("doctree", "ID") == TableColumnMetadata("INTEGER", "BINARY", false, true, true));

	db.close();

}

unittest{
	
	auto db = Database( sqlite_filename );
	Tree_Db tree = Tree_Db.createTree( db, "mytree" );

	TreeNode tree_node = tree.getTreeNode();
	NodeData nd = tree_node.node_data;
	
	assert( nd.pid == 0);
	assert( nd.e_data == "mytree");
	
	//bDebug_out = true;
	
	debug_out("tree_node-1: ", &tree_node);

	// flush the empty tree
	tree.flush();

	ResultRange results = db.execute( "select ID, e_data, p_id, t_id from doctree where id=1" );
	Row row = results.front();

	assertNDRecord( row, 1, "mytree", 0, TreeNodeType.tree );

	//bDebug_out = true;
	
	debug_out("tree_node-2: ", &tree_node);
	
	tree_node.appendChild( TreeNodeType.docType, "html" );
	auto tn_html = tree_node.appendChild( TreeNodeType.element, "html" );
	
	auto tn_head = tn_html.appendChild( TreeNodeType.element, "head" );
	tn_head.appendChild( TreeNodeType.comment, "This is my comment" );
	
	auto tn_body = tn_html.appendChild( TreeNodeType.element, "body" );
	
	tn_body.appendChild( TreeNodeType.text, "This is some text" );
	tn_body.appendChild( TreeNodeType.text, " with more text" );
	tn_body.appendChild( TreeNodeType.element, "input" );
	
	
	tree.flush();

	//bDebug_out = false;

	string html_out = tree.getTreeAsText( );	
	//writeln( html_out );
	assert( html_out == "<DOCTYPE html><html><head><!--This is my comment--></head><body>This is some text with more text<input/></body></html>");
	

}


unittest{

	writeln( "Testing DocOrderIterator" );

	auto db = Database( sqlite_filename );
	TreeNameID[] tree_list = Tree_Db.getTreeList( db );	
	Tree_Db tree = Tree_Db.loadTree( db, tree_list[0].tree_id );
	
	TreeNode tree_node = tree.getTreeNode();
	
	DocOrderIterator it = new DocOrderIterator( tree_node );
	int i=0;
	TreeNode nxt;
	while( (nxt=it.nextNode) !is null ){		
		switch(i){
		case 0:
			assert( nxt.node_data.type == TreeNodeType.tree );
			break;
			
		case 1:
			assert( nxt.node_data.type == TreeNodeType.docType );
			break;

		case 2,3,5,8:
			assert( nxt.node_data.type == TreeNodeType.element );
			break;

		case 4:
			assert( nxt.node_data.type == TreeNodeType.comment );
			break;

		case 6,7:
			assert( nxt.node_data.type == TreeNodeType.text );
			break;

		default:
		}
		i+=1;
	}
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
	db.run("insert into params(Name, Val) values('DB_VERSION','"~to!string(db_ver)~"')");
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

string get_openTag_commence( TreeNodeType nt, string e_data ){
	
	switch( nt ){
	
	case TreeNodeType.text:
		return e_data;
		
	case TreeNodeType.comment:
		return "<!--"~e_data;
		
	case TreeNodeType.docType:
		return "<DOCTYPE "~e_data;

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

struct NodeData {
	
	long ID;
	string e_data;
	long pid;
	TreeNodeType type;
	bool dirty = false;
	long orig_pid=0;
	
	this( long ID, string e_data, long pid, TreeNodeType type){
		this.ID = ID;
		this.e_data = e_data;
		this.pid = pid;
		this.type = type;
	}
}

struct TreeNameID {
	long tree_id;
	string name;
}

/**
 * TreeNode is a class because we need the references to remain valid when we modify containers such as
 * the hashmap which indexes on ID.
 * 
 * If we use a struct, then we need to hold the TreeNode data somewhere in order to use a pointer to the data. If
 * we move the data, such as updating a map, then all the pointers need to change, or we need pointers to pointers.
 * Either is not ideal. If we use references, as provided by a class, then the GC will track the references and ensure
 * that they remain valid. We can move the references knowing that the data remains in place on the heap
 * 
 */
class TreeNode {
	
	private:
	
		Tree_Db owner_tree;

		/**
		 * Set the node ID of this treenode. Also sets the parent IDs of all child nodes and updates
		 * the owner_tree hashmap
		 */
		long setNodeId( long nnid ){
			
			long oldid = node_data.ID;
			
			node_data.ID = nnid;
			foreach(child; child_nodes ){
				child.node_data.pid = nnid;
			}
			
			owner_tree.all_nodes[nnid] = this;
			owner_tree.all_nodes.remove( oldid );
			
			return nnid;
		}
	
	// end private
	
	public:
	
		NodeData 		node_data;
		TreeNode[] 		child_nodes;
		bool				dirty;	// true indicates a change in child_nodes

		this( Tree_Db owner_tree, NodeData node_data){
			this.owner_tree = owner_tree;
			this.node_data = node_data;
		}
		
		/**
		 * Returns the parent node of this node or null if no parent exists (i.e. tree-root)
		 */
		TreeNode parentNode(){
			if(node_data.pid==0) return null;
			return owner_tree.getTreeNodeById( node_data.pid );
		}
		
		/**
		 * Returns the next sibling of this node or null if none exists
		 */
		TreeNode nextSibling(){
			if(node_data.pid==0) return null;
			
			//bDebug_out = true;
			TreeNode p_node = owner_tree.getTreeNodeById( node_data.pid );
			if(p_node is null){
				debug_out("(ID,e_data) = ", node_data.ID, node_data.e_data );
				throw new Exception("oops");
			}
			
			foreach( i, c_node; p_node.child_nodes){
				if(c_node==this){
					if( i == p_node.child_nodes.length-1) return null;
					return p_node.child_nodes[i+1];
				}
			}
			throw new Exception("Damaged tree, possibly incorrect parent id for a child.");
		}

		bool hasChildNodes(){
			return child_nodes.length>0;
		}

		TreeNode firstChild(){
			if( child_nodes.length==0 ) return null;
			return child_nodes[0];
		}

		/**
		 * Set the data for this node.
		 * 
		 * The data is interpreted using the type of node. For example, the text content of a text node is
		 * the data whereas for element types, the data is used to hold the element name.
		 */
		void setData( string nData ){
			node_data.e_data = nData;
			node_data.dirty = true;
		}
		
		/**
		 * Insert a new child node at the position indicated.
		 */
		TreeNode insertChild( TreeNodeType n_type, string e_data, int pos ){		
			return owner_tree.insertChild( this, n_type, e_data, pos );		
		}

		/**
		 * Append a new child node.
		 */
		TreeNode appendChild( TreeNodeType n_type, string e_data ){
			return owner_tree.insertChild( this, n_type, e_data, cast(int)(child_nodes.length) );
		}
		
		void moveNode( TreeNode new_p_node, int pos ){
			owner_tree.moveNode( this, new_p_node, pos );
		}
	
		void cutChild( TreeNode c_node ){
			foreach( i, child; child_nodes ){
				if(child == c_node ){
					removeAt!TreeNode( child_nodes, cast(int)(i) );
					dirty = true;
					return;
				}
			}
			throw new Exception( format("Node %d is not a child of node %d ", c_node.node_data.ID, node_data.ID) );
		}
				
	// end public
	
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
		long nnid = 0;		
		
		TreeNode[long]	all_nodes;  //https://dlang.org/spec/hash-map.html

		long getNextNodeId(){
			nnid -= 1;
			return nnid;
		}
		
	// end protected

	private:

		this( Database* db, long tid, string tree_name = null ){
			
			this.db = db;
			
			if(tid==0){
				//new tree
				tree_id = getNextNodeId();
				TreeNode tn = new TreeNode( 
					this, 
					NodeData( tree_id, tree_name, 0, TreeNodeType.tree)
				);
				this.all_nodes[ tree_id ] = tn;
				return;
			}
			
			tree_id = tid;
				
			//load the tree in one hit using the tree_id
			//also order by the parent_id so that we know all siblings are grouped together
			//and then by child order
		
			auto results = db.execute( format("select ID, e_data, p_id, t_id from doctree where tree_id=%d or id=%d order by p_id,c_order", tid, tid) );
			foreach (row; results){
				
				long id = row.peek!long(0);
				long p_id = row.peek!long(2);
				TreeNode tn = new TreeNode( this, NodeData(
					id,
					row.peek!string(1),
					p_id,
					getTreeNodeType( row.peek!int(3) )
				));
				all_nodes[id] = tn;
				if(p_id==0) continue;
				all_nodes[p_id].child_nodes ~= all_nodes[id];
			}
		}
	
	// end private
	

	public:
	
	static void db_create_schema( ref Database db ){		
		db.run("CREATE TABLE IF NOT EXISTS doctree (ID INTEGER, e_data	TEXT,p_id INTEGER,t_id INTEGER NOT NULL,tree_id INTEGER NOT NULL,	c_order INTEGER, PRIMARY KEY( ID AUTOINCREMENT))");
	}

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
	
	/**
	 * Create a new tree in RAM. No database activity takes place at this time.
	 */
	static Tree_Db createTree( ref Database db, string tree_name ){
		return new Tree_Db( &db, 0, tree_name );		
	}

	/**
	 * Load a tree into RAM from database given the tree ID.
	 */
	static Tree_Db loadTree( ref Database db, long tree_id ){
		return new Tree_Db( &db, tree_id );		
	}	
	
	/**
	 * Returns the root node of this tree. This is special node holds the tree name and ID and is not
	 * usually part of the document but rather the parent container.
	 */
	TreeNode getTreeNode(){
		return all_nodes[tree_id];
	}

	/**
	 * Return any node given its ID. 
	 * 
	 * Note about IDs:
	 * 	positive IDs indicate that the record exists on the database and the ID is the database ID of that node.
	 * 	negative IDs indicate that the record is a new one existing in RAM only until such times as 'flush' is called.
	 * 
	 */
	TreeNode getTreeNodeById( long id ){
		
		TreeNode* ps = id in all_nodes;
		if(ps) return all_nodes[id];
		debug_out("getTreeNodeById: did not find key ", id );
		return null;
	}

	/**
	 * Return the tree as html text. This is the cached tree with all changes and not from the database.
	 */
	string getTreeAsText( ){
		return getTreeAsText_r( all_nodes[tree_id] );
	}


	/**
	 * Create and insert a new child into the parent node (p_node) at the position (pos) indicated.
	 */
	TreeNode insertChild( TreeNode p_node, TreeNodeType n_type, string e_data, int pos ){
				
		/* Algorithm:
		add into the correct place in ram, assign a new id <=-1. 
		An ID is required to add to the map. Using negative IDs indicates that it is not a DB ID.
		Mark the TreeNode parent as dirty indicating that children need adding and re-ordering
		flush: insert (into db) all nodes first then set c_order column for those with dirty parents(!)
		*/
	
		long id = getNextNodeId();
		TreeNode tn = new TreeNode( 
			this, 
			NodeData( id, e_data, p_node.node_data.ID, n_type)
		);
		
		this.all_nodes[ id ] = tn;		
		p_node.child_nodes.insertInPlace( pos, this.all_nodes[ id ]);
		p_node.dirty = true;
		return tn;
	}

	/**
	 * Move the given node (nodeToMove) to the new parent (nodeDestParent) inserting at position pos.
	 * Currently only works for node relocation within the same tree.
	 * 
	 */
	void moveNode( TreeNode nodeToMove, TreeNode nodeDestParent, int pos ){
		/* Algorith:
		Move the node and all children into new parent (same parent also works)
		Mark old parent TreeNode as dirty indicating a re-order is necessary
		Mark new parent TreeNode as dirty indicating a re-order is necessary
		update parent id of moved child
		flush: locate the node using it's original id except if negative
				update the db with the new ID and set orig_id=0;
		*/
		
		// 1st remove node
		auto old_p = nodeToMove.parentNode();
		if(nodeDestParent == old_p){
			// same parent, nothing to do except move in-place and re-order
			old_p.cutChild( nodeToMove );
			old_p.child_nodes.insertInPlace( pos, nodeToMove );
			old_p.dirty = true;
			return;
		}
		
		old_p.cutChild( nodeToMove );
				
		// add node to new parent
		nodeDestParent.child_nodes.insertInPlace( pos, nodeToMove );
		nodeDestParent.dirty = true;
		nodeToMove.node_data.pid = nodeDestParent.node_data.ID;
		nodeToMove.node_data.dirty = true;	//dirty data will suffice for storing pid too
	}
	
	/**
	 * Save all edits to the tree to the database. After this call, the database values will be in sync
	 * with the memory tree.
	 */
	void flush(){		
		
		// nodes must be written in document order so that a valid database ID is always available as a parent
		//ID for subsequent child writes. This is because the child update will write

		debug_out("flush():");

		long new_tree = tree_id<0;

		DocOrderIterator it = new DocOrderIterator( all_nodes[tree_id] );
		TreeNode tnode;
		while( (tnode=it.nextNode) !is null ){
			
			NodeData* nd = &tnode.node_data;
			debug_out("next node:", *nd );
				
			//first we check the ID<0 which implies it is a new node	
			if( nd.ID<0 ){

				if(new_tree) tree_id=0;
				
				db.run( format("insert into doctree(e_data, p_id, t_id, tree_id ) values( '%s', %d, %d, %d )", nd.e_data, nd.pid, nd.type, tree_id ) );

				//update the node id
				long newID = tnode.setNodeId( db.lastInsertRowid );
				if(new_tree) tree_id = newID;
				
			}else if( nd.dirty ){
				//dirty data and possibly pid too
				db.run( format("update doctree set e_data='%s', p_id=%d where id=%d", nd.e_data, nd.pid, nd.ID ) );
				nd.dirty = false;
			}
		}

		//Re-enumerate any children that have shifted positions (or are new) according to their array positions
		it.reset();
		while( (tnode=it.nextNode) !is null ){
			if( tnode.dirty ){
				foreach( i, cNode; tnode.child_nodes){
					db.run( format("update doctree set c_order=%d where id=%d", i, cNode.node_data.ID ) );
				}
				tnode.dirty = false;
			}
		}
	}

	protected:
	
	string getTreeAsText_r( ref TreeNode tn ){
		
		string strRtn = "";

		TreeNode[] children = tn.child_nodes;
		foreach( child; children){
			NodeData nd = child.node_data;
			strRtn ~= get_openTag_commence( nd.type, nd.e_data );
			// --> add attributes if required
			strRtn ~= get_openTag_end( nd.type, nd.e_data );
			strRtn ~= getTreeAsText_r( child );
			strRtn ~= get_closeTag( nd.type, nd.e_data );
		}
		
		return strRtn;
	}
	
}
/*
  
 Delete node (branch)
	If the id<=-1, then it was a new node, unsaved, can be removed entirely
	Otherwise, move the node and all children into a delete-map.	
	Mark the TreeNode parent as dirty indicating that children need removing. Re-ordering is
	not required but may be advantageous
	flush: Delete entries using the delete-map and clear the map.

 Move node
	Move the node and all children into new parent (same parent also works)
	Mark old parent TreeNode as dirty indicating a re-order is necessary, re-order ram children
	Mark new parent TreeNode as dirty indicating a re-order is necessary, re-order ram children
	update parent id of moved child
	
 */ 
 
unittest{

	writeln( "Testing tree loading" );

	auto db = Database( sqlite_filename );
		
	auto tree2 = Tree_Db.createTree( db, "AnotherTree" );
	tree2.flush();
	
	TreeNameID[] tree_list = Tree_Db.getTreeList( db );
	assert( tree_list.length==2 );
	
	Tree_Db tree = Tree_Db.loadTree( db, tree_list[0].tree_id );
	
	TreeNode tree_node = tree.getTreeNode();
	NodeData nd_t = tree_node.node_data;
	assert( nd_t.ID == tree_list[0].tree_id );
	assert( nd_t.e_data == tree_list[0].name );
	assert( nd_t.pid == 0 );
	assert( nd_t.type == TreeNodeType.tree );

	TreeNode html_node;
	
	int i=0;
	foreach( node_ptr; tree_node.child_nodes ){		

		NodeData c_node = node_ptr.node_data;
		
		switch(i){
		case 0:
			assert( c_node.ID == 2 );
			assert( c_node.e_data == "html" );
			assert( c_node.pid == tree_list[0].tree_id );
			assert( c_node.type == TreeNodeType.docType );
			break;

		case 1:
			html_node = node_ptr;
			assert( c_node.ID == 3 );
			assert( c_node.e_data == "html" );
			assert( c_node.pid == tree_list[0].tree_id );
			assert( c_node.type == TreeNodeType.element );
			break;
		
		default:
		}
	
		i+=1;
	}
	
	string html_out = tree.getTreeAsText( );	
	assert( html_out == "<DOCTYPE html><html><head><!--This is my comment--></head><body>This is some text with more text<input/></body></html>");

	writeln( "Testing tree element insertion" );

	//get head element
	TreeNode tn_head = html_node.child_nodes[0];	
	
	//add an element to the head at position zero
	tn_head.insertChild( TreeNodeType.element, "script", 0 );	
	
	html_out = tree.getTreeAsText( );	
	assert( html_out == "<DOCTYPE html><html><head><script></script><!--This is my comment--></head><body>This is some text with more text<input/></body></html>");

	writeln( "Testing tree editing" );

	//edit the comment node (id=5)
	TreeNode e_comment = tree.getTreeNodeById( 5 );	
	e_comment.setData( "An edit took place" );
	
	html_out = tree.getTreeAsText( );	
	assert( html_out == "<DOCTYPE html><html><head><script></script><!--An edit took place--></head><body>This is some text with more text<input/></body></html>");

	//check that the database entry is unchanged
	auto results = db.execute( "select e_data from doctree where id=5" );
	foreach (row; results){		
		assert( "This is my comment" == row.peek!string(0) );
	}
	
	// save to database	
	tree.flush();
		
	//check db contents using a new tree
	Tree_Db tree3 = Tree_Db.loadTree( db, tree_list[0].tree_id );
	html_out = tree3.getTreeAsText( );	
	assert( html_out == "<DOCTYPE html><html><head><script></script><!--An edit took place--></head><body>This is some text with more text<input/></body></html>");

	writeln("Testing moveNode");
	
	//use the original tree to test a move the comment node	
	auto tn_body = tn_head.nextSibling();
	e_comment.moveNode( tn_body, 0 );
	html_out = tree.getTreeAsText( );	
	assert( html_out == "<DOCTYPE html><html><head><script></script></head><body><!--An edit took place-->This is some text with more text<input/></body></html>");
	
	//test that it flushes correctly
	tree.flush();
	auto result = db.execute( "select id, e_data, p_id, t_id from doctree where id=5" );		
	assertNDRecord( result.front(), 5, "An edit took place", tn_body.node_data.ID, TreeNodeType.comment );
	
	writeln("TODO: Test multiple moveNode");		
}


/**
 * Iterator starting at any given TreeNode, traversing each of the descendent nodes, depth first and increasing child index.
 */
class DocOrderIterator {
	
	TreeNode start_node;
	TreeNode next_node;
	
	this( TreeNode n ){
		start_node = n;
		next_node = n;
	}
	
	void reset(){
		next_node = start_node;		
	}
	
	/**
	 * The initial TreeNode is the first node to be returned.
	 */
	TreeNode nextNode(){
	
		//the node we will return this time
		TreeNode rtnNode = next_node;
		if(rtnNode is null) return null;
			
		//now work out the node for the next call
				
		if( rtnNode.hasChildNodes() ){
			next_node = rtnNode.firstChild();			
			return rtnNode;
		}
		
		TreeNode anc_node = rtnNode;
		while( anc_node !is null && anc_node.nextSibling() is null){
			anc_node = anc_node.parentNode();
			if( anc_node == start_node ){
				anc_node=null;
				break;
			}
		}
		if(anc_node is null) {
			next_node=null;
			return rtnNode;
		}
		
		next_node = anc_node.nextSibling();
		return rtnNode;
	
	}
	
}


void removeAt(T)( ref T[] t, int pos ){
	
	//I really don't like these re-assignments
	//t = t.remove(pos);
	//t = t[0..pos] ~ t[pos+1..$]
	
	for( int i=pos; i<t.length-1; i++){
		t[i] = t[i+1];
	}
	t.length -= 1;
}


bool bDebug_out = false;
void debug_out(){ writeln(); }

void debug_out(T, A...)(T t, A a){
    if(!bDebug_out) return;
    import std.stdio;
    write(t);
    debug_out(a);
}
