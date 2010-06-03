package bdog.pstore;

typedef PRef = String;
typedef PIndex = { name:String, filter:Dynamic->String };

class PObj {
  public var _id:PRef;
  public var _parent:PRef;
  
  public function new() {
    _id = null;
    _parent = null;
  }
  
  public function
  insert(?cb:String->Void) {
    PMgr.driver.create(this,function(id) {
        if (cb != null) cb(id);
      });
  }

  public inline function
  rank() {
    return Std.parseInt(_id.split(":")[1]);
  }

  public function
  link(o:PObj,?cb:String->Void) {
    o.setParent(this);
    o.insert(cb);
  }
  
  public inline function
  getClass() {
    return Type.getClass(this);
  }

  public inline function
  className() {
    return Type.getClassName(getClass());
  }
  
  public function
  delete() {
    PMgr.driver.del(this);
  }

  public function
  update() {
    PMgr.driver.update(this);
  }

  public function
  setParent(p:PObj) {
    _parent = p._id;
  }

  public inline function
  ref() {
    return new String(_id);
  }

  public inline function
  parent() {
    return _parent;
  }

  public function
  sync(cb:Bool->Void) {
    PMgr.driver.sync(this,cb);
  }

  public function
  linked(inKls:Class<Dynamic>,cb:Array<Dynamic>->Void) {
    var klsName = Type.getClassName(Type.getClass(this));
    PMgr.driver.linked(inKls,ref(),0,-1,cb);
  }
}

class PMgr<T:PObj> {
  var kls:Class<T>;
  var klsName:String;

  public static var driver:PDrv;
  
  public function new(kls:Class<T>) {
    this.kls = kls;
    klsName = Type.getClassName(kls);
  }

  public function
  find(index:String,k,cb:T->Void) {
    driver.find(klsName,index,k,cb);
  }
  
  public function
  get(i:Int,cb:T->Void):Void {
    driver.get(klsName,i,cb);
  }

  public function
  load(id:String,cb:T->Void):Void {
    driver.load(id,cb);
  }

  public function
  indexed(s:Int,e:Int,index:String,cb:Array<Dynamic>->Void) {
    driver.indexed(klsName,s,e,index,cb);
  }

  public function
  insertMany(objs:Array<T>,cb:Array<String>->Void) {
    var
      l = objs.length,
      ids = new Array<String>(),
      onReturn = function(id) {
         l--;
         ids.push(id);
         if (l == 0) cb(ids);
      };

    for (o in objs) {
      o.insert(onReturn);      
    }
  }

}
