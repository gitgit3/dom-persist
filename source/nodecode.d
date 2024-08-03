/**
	COPYRIGHT © 2024 JOHN PEARCEY
	Distributed under the Boost Software License, Version 1.0.
		(See accompanying file LICENSE.txt or copy at
		https://www.boost.org/LICENSE_1_0.txt)
*/
module nodecode;

import std.traits;
import std.format;

import dom_persist;


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

/**
 * Node data held by each TreeNode.
 */
struct NodeData {
	
	long ID;			// The (database) ID of this node. negative IDs are new nodes not yet flushed
	string e_data;	// Data specific to the node. e.g. element name, or comment text etc..
	long pid;		// Parent node ID. If not connected then zero
	TreeNodeType type;
	bool dirty = false;	// true when any node data changes indicating a DB write is required.	
	
	this( long ID, string e_data, long pid, TreeNodeType type){
		this.ID = ID;
		this.e_data = e_data;
		this.pid = pid;
		this.type = type;
	}
}

/**
 * Each element in the tree is represented by an instance of TreeNode.
 * 
 * This class contains node specific operations such as reading, mutation, relocation etc..
 */
class TreeNode {
	
	private:
	
		Tree_Db owner_tree;
	
	// end private
	
	public:
	
		NodeData 		node_data;
		TreeNode[] 		child_nodes;
		bool				dirty;	// true indicates a change in child_nodes ordering

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

		TreeNode getChildAt( int pos ){
			if( child_nodes.length<=pos ) return null;
			return child_nodes[pos];
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
		 * Set the node ID of this treenode. Also sets the parent IDs of all child nodes.
		 */
		long setNodeId( long nnid ){
			
			long oldid = node_data.ID;
			
			node_data.ID = nnid;
			foreach(child; child_nodes ){
				child.node_data.pid = nnid;
			}
			return nnid;
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
	
		/**
		 * Delete this node and all it's descendents from the the tree.
		 */
		void deleteNode( ){
			owner_tree.deleteNode( this );
		}

		/**
		 * Internal use only.
		 * 
		 * Locate the child node (c_node) and snip it off.
		 */
		void cutChild( TreeNode c_node ){
			foreach( i, child; child_nodes ){
				if(child == c_node ){
					removeAt!TreeNode( child_nodes, cast(int)(i) );
					c_node.node_data.pid = 0;	//it has no parent now
					dirty = true;
					return;
				}
			}
			throw new Exception( format("Node %d is not a child of node %d ", c_node.node_data.ID, node_data.ID) );
		}
				
	// end public
	
}
