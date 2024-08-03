module dom_persist_tests;

import std.stdio;

import dom_persist;
import nodecode;

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

	class Timer{
		
		static ulong getCount(){
			asm{
				naked	;
				rdtsc	;
				ret	;
			}
		}

		ulong starttime;

		this() { starttime = getCount(); }
		
		~this(){
			ulong endtime = getCount();
			writefln("elapsed time ( %d to %d ) = %d", starttime, endtime, endtime - starttime);
		}
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

	writeln("Testing test element move");
	
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


unittest{


	int[] a1;
	
	for(int i=0; i<10000; i+=1){
		a1 ~= i;
	}
	
	{
		scope t = new Timer();
		
		for(int i=0; i<10000; i+=1){
			removeAt!int( a1, 0 );
		}
	}
	
}
