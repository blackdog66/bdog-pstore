
package bdog.pstore;

import bdog.pstore.PStore;

interface PDrv {
  function create(instance:PObj,cb:String->Void):Void;
  function get(klsName:String,i:Int,cb:Dynamic->Void):Void;
  function load(id:String,cb:Dynamic->Void):Void;
  function sync(instance:PObj,cb:Bool->Void):Void;
  function find(klsName:String,index:String,key:String,cb:Dynamic->Void):Void;
  function nextID(kls:Class<Dynamic>,cb:PRef->Void):Void;
  function update(instance:PObj):Void;
  function del(instance:PObj):Void;
  function linked(kls:Class<Dynamic>,or:PRef,s:Int,e:Int,cb:Array<Dynamic>->Void):Void;
  function indexed(klsName:String,start:Int,end:Int,index:String,cb:Array<Dynamic>->Void):Void;
}