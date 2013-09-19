package hxd.res;
import haxe.macro.Context;
import haxe.macro.Expr;

private typedef FileEntry = { e : Expr, t : ComplexType };

class FileTree {
	
	var path : String;
	var currentModule : String;
	var pos : Position;
	var loaderType : ComplexType;
	var ignoredDir : Map<String,Bool>;
	var ignoredExt : Map<String,Bool>;
	var options : EmbedOptions;
	
	public function new(dir) {
		this.path = resolvePath(dir);
		currentModule = Std.string(Context.getLocalClass());
		pos = Context.currentPos();
		ignoredDir = new Map();
		ignoredDir.set(".svn", true);
		ignoredDir.set(".git", true);
		ignoredDir.set(".tmp", true);
		ignoredExt = new Map();
		ignoredExt.set("gal", true); // graphics gale source
		ignoredExt.set("lch", true); // labchirp source
	}
	
	function resolvePath(dir:Null<String>) {
		var resolve = true;
		if( dir == null ) {
			dir = Context.definedValue("resourcesPath");
			if( dir == null ) dir = "res" else resolve = false;
		}
		var pos = Context.currentPos();
		if( resolve )
			dir = try Context.resolvePath(dir) catch( e : Dynamic ) Context.error("Resource directory not found in classpath '" + dir + "'", pos);
		var path = sys.FileSystem.fullPath(dir);
		if( !sys.FileSystem.exists(path) || !sys.FileSystem.isDirectory(path) )
			Context.error("Resource directory does not exists '" + path + "'", pos);
		return path;
	}
	
	public function embed(options:EmbedOptions) {
		if( options == null ) options = { };
		var needTmp = options.compressSounds;
		if( options.tmpDir == null ) options.tmpDir = path + "/.tmp/";
		if( options.fontsChars == null ) options.fontsChars = h2d.Font.ASCII + h2d.Font.LATIN1;
		if( needTmp && !sys.FileSystem.exists(options.tmpDir) )
			sys.FileSystem.createDirectory(options.tmpDir);
		this.options = options;
		return embedRec("");
	}
	
	function embedRec( relPath : String ) {
		var dir = this.path + relPath;
		var data = { };
		// make sure to rescan if one of the directories content has changed (file added or deleted)
		Context.registerModuleDependency(currentModule, dir);
		for( f in sys.FileSystem.readDirectory(dir) ) {
			var path = dir + "/" + f;
			if( sys.FileSystem.isDirectory(path) ) {
				if( ignoredDir.exists(f.toLowerCase()) )
					continue;
				var sub = embedDir(f, relPath + "/" + f, path);
				if( sub != null )
					Reflect.setField(data, f, sub);
			} else {
				var extParts = f.split(".");
				var noExt = extParts.shift();
				var ext = extParts.join(".");
				if( ignoredExt.exists(ext.toLowerCase()) )
					continue;
				if( embedFile(f, ext, relPath + "/" + f, path) )
					Reflect.setField(data, f, true);
			}
		}
		return data;
	}
	
	function embedDir( dir : String, relPath : String, fullPath : String ) {
		var f = embedRec(relPath);
		if( Reflect.fields(f).length == 0 )
			return null;
		return f;
	}
	
	function getTime( file : String ) {
		return try sys.FileSystem.stat(file).mtime.getTime() catch( e : Dynamic ) -1.;
	}
	
	static var invalidChars = ~/[^A-Za-z0-9_]/g;
	function embedFile( file : String, ext : String, relPath : String, fullPath : String ) {
		var name = "R" + invalidChars.replace(relPath, "_");
		if( Context.defined("flash") ) {
			switch( ext.toLowerCase() ) {
			case "wav" if( options.compressSounds ):
				var tmp = options.tmpDir + name + ".mp3";
				if( getTime(tmp) < getTime(fullPath) ) {
					if( Sys.command("lame", ["--silent","-h",fullPath,tmp]) != 0 )
						Context.warning("Failed to run lame on " + path, pos);
					else {
						fullPath = tmp;
					}
				} else {
					fullPath = tmp;
				}
			case "ttf":
				haxe.macro.Context.defineType({
					pack : ["hxd","_res"],
					name : name,
					meta : [
						{ name : ":font", pos : pos, params : [macro $v { fullPath }, macro $v { options.fontsChars } ] },
						{ name : ":keep", pos : pos, params : [] },
					],
					kind : TDClass(),
					params : [],
					pos : pos,
					isExtern : false,
					fields : [],
				});
				return false; // don't embed font bytes in flash
			default:
			}
			Context.defineType( {
				params : [],
				pack : ["hxd","_res"],
				name : name,
				pos : pos,
				isExtern : false,
				fields : [],
				meta : [
					{ name : ":keep", params : [], pos : pos },
					{ name : ":file", params : [ { expr : EConst(CString(fullPath)), pos : pos } ], pos : pos },
				],
				kind : TDClass({ pack : ["flash","utils"], name : "ByteArray", params : [] }),
			});
		} else {
			return false;
		}
		return true;
	}
	
	public function scan() {
		var fields = Context.getBuildFields();
		var dict = new Map();
		for( f in fields ) {
			if( Lambda.has(f.access,AStatic) ) {
				dict.set(f.name, "class declaration");
				if( f.name == "loader" )
					loaderType = switch( f.kind ) {
					case FVar(t, _), FProp(_, _, t, _): t;
					default: null;
					}
			}
		}
		if( loaderType == null ) {
			loaderType = macro : hxd.res.Loader;
			dict.set("loader", "reserved identifier");
			fields.push({
				name : "loader",
				access : [APublic, AStatic],
				kind : FVar(loaderType),
				pos : pos,
			});
		}
		scanRec("", fields, dict);
		return fields;
	}
	
	function scanRec( relPath : String, fields : Array<Field>, dict : Map<String,String> ) {
		var dir = this.path + "/" + relPath;
		// make sure to rescan if one of the directories content has changed (file added or deleted)
		Context.registerModuleDependency(currentModule, dir);
		for( f in sys.FileSystem.readDirectory(dir) ) {
			var path = dir + "/" + f;
			var fileName = f;
			var field = null;
			var ext = null;
			if( sys.FileSystem.isDirectory(path) ) {
				if( ignoredDir.exists(f.toLowerCase()) )
					continue;
				field = handleDir(f, relPath.length == 0 ? f : relPath+"/"+f, path);
			} else {
				var extParts = f.split(".");
				var noExt = extParts.shift();
				ext = extParts.join(".");
				if( ignoredExt.exists(ext.toLowerCase()) )
					continue;
				field = handleFile(f, ext, relPath.length == 0 ? f : relPath + "/" + f, path);
				f = noExt;
			}
			if( field != null ) {
				var other = dict.get(f);
				if( other != null ) {
					Context.warning("Resource " + relPath + "/" + f + " is used by both " + relPath + "/" + fileName + " and " + other, pos);
					continue;
				}
				dict.set(f, relPath + "/" + fileName);
				fields.push({
					name : f,
					pos : pos,
					kind : FProp("get","never",field.t),
					access : [AStatic, APublic],
				});
				fields.push({
					name : "get_" + f,
					pos : pos,
					kind : FFun({
						args : [],
						params : [],
						ret : field.t,
						expr : { expr : EMeta({ name : ":privateAccess", params : [], pos : pos }, { expr : EReturn(field.e), pos : pos }), pos : pos },
					}),
					meta : [ { name:":extern", pos:pos, params:[] } ],
					access : [AStatic, AInline],
				});
			}
		}
	}
	
	function handleDir( dir : String, relPath : String, fullPath : String ) : FileEntry {
		var ofields = [];
		var dict = new Map();
		dict.set("loader", "reserved identifier");
		scanRec(relPath, ofields, dict);
		if( ofields.length == 0 )
			return null;
		var name = "R" + (~/[^A-Za-z0-9_]/g.replace(fullPath, "_"));
		for( f in ofields )
			f.access.remove(AStatic);
		var def = macro class {
			public inline function new(loader) this = loader;
			var loader(get,never) : $loaderType;
			inline function get_loader() : $loaderType return this;
		};
		for( f in def.fields )
			ofields.push(f);
		Context.defineType( {
			pack : ["hxd", "_res"],
			name : name,
			pos : pos,
			meta : [{ name : ":dce", params : [], pos : pos }],
			isExtern : false,
			fields : ofields,
			params : [],
			kind : TDAbstract(loaderType),
		});
		var tpath = { pack : ["hxd", "_res"], name : name, params : [] };
		return {
			t : TPath(tpath),
			e : { expr : ENew(tpath, [macro loader]), pos : pos },
		};
	}
	
	function handleFile( file : String, ext : String, relPath : String, fullPath : String ) : FileEntry {
		var epath = { expr : EConst(CString(relPath)), pos : pos };
		switch( ext.toLowerCase() ) {
		case "jpg", "png":
			return { e : macro loader.loadTexture($epath), t : macro : hxd.res.Texture };
		case "fbx", "xbx":
			return { e : macro loader.loadModel($epath), t : macro : hxd.res.Model };
		case "ttf":
			return { e : macro loader.loadFont($epath), t : macro : hxd.res.Font };
		case "wav", "mp3":
			return { e : macro loader.loadSound($epath), t : macro : hxd.res.Sound };
		default:
			return { e : macro loader.loadData($epath), t : macro : hxd.res.Resource };
		}
		return null;
	}
	
	public static function build( ?dir : String ) {
		return new FileTree(dir).scan();
	}
	
}