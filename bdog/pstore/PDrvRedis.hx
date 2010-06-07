package bdog.pstore; 

import bdog.Event;
import bdog.redis.Redis;
import bdog.SeqRand;

import bdog.pstore.PStore;
import bdog.pstore.PDrv;

private class RPool {
  static var pool = new Array<RedisClient>();
  
  public function new(nConns:Int) {
    for (c in 0...nConns) {
      pool.push(Redis.newClient());
    }
  }

  public function
  use(cb:RedisClient->Void) {
    var p = null;
    try {
      p = ((pool.length) > 0) ? pool.shift() : Redis.newClient();
      cb(p);
    } catch(exc:Dynamic) {
      trace("pool except: "+exc);
    }
    if (p != null) {
      pool.push(p);
    }
  }
}

class PDrvRedis implements PDrv {
  static var ALL = "all:";
  static var HASH = "h_";
  static var ZSET = "z_";
  static var SET = "s_";
  static var SERIAL = "serial:";
  static var TEXT = "t_";
  static var OBJECT = "object";
  
  public static var pool = new RPool(5);

  public static function ignore(e,v) {}

  public function new() {}
  
  public function
  create(instance:PObj,cb:String->Void) {
    var
      kls = Type.getClass(instance),
      klsName = Type.getClassName(kls),
      insert = function(id:String) {
         var
         sid = klsName + ":" + id;
         
          if (instance._id == null)
            instance._id = sid;
          
          pool.use(function(conn) {
              var o:Array<Dynamic> = [sid,OBJECT,haxe.Serializer.run(instance)];
              if (instance._parent != null) {
                o.push("parent");
                o.push(instance._parent);

                conn.lpush(instance._parent+":children"+":"+klsName,sid,ignore);
              }

              conn.rpush(ALL+klsName,sid,function(e,v) {
                  o.push("position");
                  o.push(v);
                  conn.hmset(o,function(e,v) {
                      indexEntry(conn,kls,klsName,instance);
                      //instances.set(sid,instance);
                      if (cb != null) {
                        cb(sid);
                      }
                    });
                });
            });
    }
    
    if (instance._id == null) {
      nextID(kls,insert);
    } else {
      insert(instance._id);
    }
  }

  public function
  get(klsName:String,i:Int,cb:Dynamic->Void) {
    var me = this;
    pool.use(function(conn) {
        conn.lindex(ALL+klsName,i,function(e,v) {
            me.load(v,cb);
          });
      });

  }
  public function
  load(id:String,fn:Dynamic->Void) {
    pool.use(function(conn) {
        conn.hget(id,OBJECT,function(err,v) {
          if (v != null) {
            var obj = haxe.Unserializer.run(new String(v));
            //instances.set(id,obj);
            fn(obj);
          }
        });
        
    });
  }

  public function
  sync(instance:PObj,cb:Bool->Void) {
    var kls = Type.getClass(instance);
    load(Std.string(instance._id),function(newObj) {
        for (f in Reflect.fields(instance)) {
          var nval = Reflect.field(newObj,f);
          Reflect.setField(instance,f,nval);
        }
        cb(true);
      });
  }

  public function
  find(klsName:String,index:String,key:String,cb) {
    var me = this;
    pool.use(function(conn) {
        conn.hget(indexName(klsName,index),key,function(err,id) {
            if (id != null) {
              trace("trying to load "+id);
              me.load(id,cb);
            } else
              cb(null);
          });
      });
  }
  
  static function
  getScore(s:String) {
    var score = 0;
    for (i in 0...s.length) {
      if (i < 4)
        score += s.charCodeAt(i) * (256^(3-i));
      else break;
    }
    return score;      
  }

  static function
  createChildren(instance:PObj) {
    if (instance._parent != null) {
      pool.use(function(conn) {
          conn.set(instance._id + ":parent",instance._parent,function(e,v) {
            });
      });
    }
  }
  
  public function
  nextID(kls:Class<Dynamic>,cb:PRef->Void) {
    pool.use(function(conn) {
        var klsName = Type.getClassName(kls);
        conn.incr(SERIAL+klsName,function(e,id) {
            cb(Std.string(id));  
          });
      });
  }

  public function
  update(instance:PObj,cb:Bool->Void) {
    var
      kls = Type.getClass(instance),
      klsName = Type.getClassName(kls),
      obj = haxe.Serializer.run(instance);

    pool.use(function(conn) {
        conn.hset(instance.ref(),OBJECT,obj,function(e,v) {
            if (e == null) {
              indexEntry(conn,kls,klsName,instance);
              cb(true);
            } else {
              cb(false);
            }
            
          });
      });
  }

  public function
  rm(instance:PObj) {
    var
      id = instance.ref();
    pool.use(function(conn) {
        // this should be MULTI/EXEC when it exists
        conn.lrem(ALL+instance.className(),1,id,function(e,v) {
            delIndexEntry(instance);
            //instances.remove(id);
          });
      });
  }
  
  static inline function
  indexName(klsName,name) {
    return "index:"+klsName+":"+name;
  }
  
  static function
  indexEntry(conn:RedisClient,kls:Class<Dynamic>,klsName:String,instance:PObj) {
    eachIndex(instance,function(index) {
        if (index.filter == null) throw "An index must have a filter function";

        var val = index.filter(instance);
          
        if (val != null) {
          //var s = getScore(val);
          conn.hset(indexName(klsName,index.name),val,instance.ref(),ignore);
          //conn.set(val,instance.ref(),function(e,v) {});
        }
      });
  }

  static function
  delIndexEntry(instance:PObj) {
    pool.use(function(conn) {
        eachIndex(instance,function(index) {
            conn.hdel(indexName(instance.className(),index.name),instance.ref(),ignore);
          });
      });
  }
  
  static function
  eachIndex(instance:PObj,cb:PIndex->Void) {
    var kls = instance.getClass();
    for (kf in Type.getClassFields(kls)) {
      if (kf == "_indexOn") {
        var indexes:Array<PIndex> = Reflect.field(kls,kf);
        for (index in indexes) {
          cb(index);
        }
      }
    }
  }

  public function
  linked<T>(inKls:Class<T>,forObject:PRef,start:Int,end:Int,cb:Array<T>->Void) {
    var
      klsName = Type.getClassName(inKls),
      spec = [forObject+":children:"+klsName,"limit",start,end,"get","*->"+OBJECT];
    sorted(spec,cb);
  }

  public function
  indexed(klsName:String,start:Int,end:Int,index:String,cb:Array<Dynamic>->Void) {
    var spec = ["index:"+klsName+":"+index,"by","nosort","limit",start,end,"get","*->"+OBJECT];
    sorted(spec,cb);
  }

  public function
  range<T>(klsName:String,start:Int,end:Int,cb:Array<T>->Void) {
    pool.use(function(conn) {
        sorted([ALL+klsName,"limit",start,end,"get","*->"+OBJECT],cb);
      });
  }

  static function
  sorted<T>(spec:Array<T>,cb:Array<T>->Void) {
    trace("spec is "+spec);
    pool.use(function(conn) {
        conn.sort(spec,function(e,members) {
            getObjects(members,cb);
        });
      });
  }

  static function
  getObjects<T>(members:Array<Dynamic>,cb:Array<T>->Void) {
    if (members != null) {
      var objArr:Array<T> = new Array();
      while(members.length > 0) {
        objArr.push(haxe.Unserializer.run(new String(members.shift())));
      }
      cb(objArr);
    }
  }
}
