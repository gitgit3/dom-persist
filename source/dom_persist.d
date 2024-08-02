module dom_persist;

import std.file;
import std.array;	//https://dlang.org/phobos/std_array.html
import std.algorithm; //https://dlang.org/phobos/std_algorithm_mutation.html
import std.conv;
import std.stdio;
import std.format;
import std.exception : enforce;
import std.traits;
import nodecode;

import d2sqlite3;	// https://d2sqlite3.dpldocs.info/v1.0.0/d2sqlite3.database.Database.this.html
						// https://dlang-community.github.io/d2sqlite3/d2sqlite3.html


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

struct TreeNameID {
	long tree_id;
	string name;
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
		/* Algorithm:
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

/*
 Delete node (branch)
	If the id<=-1, then it was a new node, unsaved, can be removed entirely
	Otherwise, move the node and all children into a delete-map.	
	Mark the TreeNode parent as dirty indicating that children need removing. Re-ordering is
	not required but may be advantageous
	flush: Delete entries using the delete-map and clear the map.
	
 */ 

	
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
				long oldid = tnode.node_data.ID;
				long nnid = db.lastInsertRowid;
				
				long newID = tnode.setNodeId( nnid );
				all_nodes[nnid] = tnode;
				all_nodes.remove( oldid );
			
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
	
	// tests on a 10000 item array

	//I really don't like these re-assignments but the ref makes it stay in-place
	
	// by far the fastest
	// 15290 cpu cycles	
	t = t[0..pos] ~ t[pos+1..$];
	
	// my implementation cpu 116100 cycles
	/*for( int i=pos; i<t.length-1; i++){
		t[i] = t[i+1];
	}
	t.length -= 1;
	*/

	// by far the slowest 154000 cpu cycles
	//t = t.remove(pos);					

}


bool bDebug_out = false;
void debug_out(){ writeln(); }

void debug_out(T, A...)(T t, A a){
    if(!bDebug_out) return;
    import std.stdio;
    write(t);
    debug_out(a);
}

