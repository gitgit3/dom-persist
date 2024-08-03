module attributeHandler;

/**
 * Module mainly for attribute parsing for DB retrieval, and some other
 * common attribute functionality
 */

import std.stdio;


/**
 * Simple attribute parser.
 * 
 * Remember to escape the " and/or ' with &quot; or &apos; if these values are required.
 */
class AttribParser {
	
	string 			strAtts;
	string[string]	mapAtts;
	
	this( string strAtts ){
		this.strAtts = strAtts;
	}
	
	ref string[string] getAsMap(){
		
		if(mapAtts !is null ) return mapAtts;
		
		int state = 0;
		string nxtKey = "";
		string nxtVal = "";
		char cQtp = '\0';
		
		foreach( i,c; strAtts ){
			
			switch(state){
			case 0:
				// wait for a key
				switch(c){
				
				case '>':
					//this is the end of the element tag
					return mapAtts;
					
				case ' ', '\t':
					break;
					
				default:
					state += 1;
					nxtKey ~= c;					
				}
				break;
				
			case 1:
				//parsing a key
				switch(c){
					
				case ' ':
					if(nxtKey=="") break;
					goto case '=';
					
				case '=':
					state += 1;					
					break;

				default:
					nxtKey ~= c;					
				}
				break;
			
			case 2:
				
				//waiting for a value
				switch(c){
				case '"', '\'':
					cQtp = c;
					state += 1;					
					break;
					
				case '=', ' ', '\t':				
					break;
					
				default:
					// not a quote, must be the next attribute and the previous att has an empty value					
					mapAtts[nxtKey] = "";
					nxtKey = ""~c;
					state=0;
				}
				break;
				
			case 3:
				//looking for the value end, must be a quote
				switch(c){
					
				case '"','\'':
					if(cQtp!=c){
						nxtVal ~= c;
						break;
					}
					mapAtts[nxtKey] = nxtVal;
					nxtKey = "";
					nxtVal = "";
					state = 0;					
					break;
					
				default:
					nxtVal ~= c;
				}
				break;

			default:
			}
		}		
		return mapAtts;
	}
	
}


unittest{

	string strAtts = "  color=\"red\" 	font='big font'  nowrap v-align='top' border=\"\"  ";
	AttribParser atts = new AttribParser( strAtts );
	
	auto attMap =  atts.getAsMap();
	foreach( key; attMap.keys() ){
		
		string value = attMap[key];
		
		switch(key){
			
		case "color":
			assert( value=="red");
			break;
			
		case "font":
			assert( value=="big font");
			break;
			
		case "nowrap":
		case "border":
			assert( value=="");
			break;
			
		case "v-align":
			assert( value=="top");
			break;
			
		default:	
			writeln("unknown key was: ", key);
			assert(false);
		}
	}

	
	atts = new AttribParser( "" );
	attMap =  atts.getAsMap();
	assert( attMap.length==0 );

	atts = new AttribParser( "color='pink' > other garbage" );
	attMap =  atts.getAsMap();
	assert( attMap.length==1 );	
	assert( attMap["color"]=="pink" );
	
}
