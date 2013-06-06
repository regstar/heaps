package h2d.comp;

class Component extends Sprite {
	
	public var name(default, null) : String;
	public var id(default, set) : String;
	public var parentComponent(default, null) : Component;
	var classes : Array<String>;
	
	var innerWidth : Float;
	var innerHeight : Float;
	var style : Style;
	var customStyle : Style;
	var styleSheet : CssEngine;
	var needRebuild : Bool;
	
	public function new(name,?parent) {
		super(parent);
		this.name = name;
		classes = [];
		needRebuild = true;
	}
		
	override function onAlloc() {
		// lookup our parent component
		var p = parent;
		while( p != null ) {
			var c = flash.Lib.as(p, Component);
			if( c != null ) {
				parentComponent = c;
				super.onAlloc();
				return;
			}
			p = p.parent;
		}
		parentComponent = null;
		super.onAlloc();
	}
	
	public function addCss(cssString) {
		if( styleSheet == null ) evalStyle();
		styleSheet.addRules(cssString);
		rebuildAll(this);
	}
	
	function rebuildAll(s:h2d.Sprite) {
		var c = flash.Lib.as(s, Component);
		if( c != null ) c.needRebuild = true;
		for( sub in s )
			rebuildAll(sub);
	}
	
	public function setStyle(?s) {
		customStyle = s;
		needRebuild = true;
		return this;
	}
	
	public function getClasses() : Iterable<String> {
		return classes;
	}
	
	public function addClass( name : String ) {
		if( !Lambda.has(classes, name) ) {
			classes.push(name);
			needRebuild = true;
		}
		return this;
	}
	
	public function toggleClass( name : String ) {
		if( !classes.remove(name) )
			classes.push(name);
		needRebuild = true;
		return this;
	}
	
	public function removeClass( name : String ) {
		if( classes.remove(name) )
			needRebuild = true;
		return this;
	}
	
	function set_id(id) {
		this.id = id;
		needRebuild = true;
		return id;
	}
	
	function getFont() {
		return Style.getFont(style.fontName, Std.int(style.fontSize));
	}
	
	function evalStyle() {
		if( parentComponent == null ) {
			if( styleSheet == null )
				styleSheet = Style.getDefault();
		} else {
			styleSheet = parentComponent.styleSheet;
			if( styleSheet == null ) {
				parentComponent.evalStyle();
				styleSheet = parentComponent.styleSheet;
			}
		}
		styleSheet.applyClasses(this);
	}
	
	function rebuild() {
	}
	
	override function sync( ctx : RenderContext ) {
		if( needRebuild ) {
			needRebuild = false;
			rebuild();
		}
		super.sync(ctx);
	}
	
}