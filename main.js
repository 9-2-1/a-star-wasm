let iconv = require("iconv-lite");
let fs = require("fs");

(async () => {
	function test(name, value, expect){
		if(value === expect){
			console.log("测试点 "+name+" 通过");
		}else{
			console.log("测试点 "+name+" 错误: ");
			console.log("  "+JSON.stringify(value)+" 不等于 "+JSON.stringify(expect));
		}
	}

	let wabt = await (require("wabt")());
	// let module = wabt.readWasm(fs.readFileSync("main.wasm"), { readDebugNames: true});
	let wast = fs.readFileSync("main.wast").toString();
	let transfer = iconv.encode(wast, "ascii");
	let module = wabt.parseWat("main.wast", transfer);
	module.validate();

	let bin = module.toBinary({}).buffer;
	module.destroy();
	fs.writeFileSync("main.wasm",bin);

	let wmodule = await WebAssembly.compile(bin);
	let instance;

	// 测试 内存拓展
	if(true){
		instance = await WebAssembly.instantiate(wmodule);
		test("内存 1",instance.exports.getPage(),1);
		test(2,instance.exports.growSize(1),1);
		test(3,instance.exports.getPage(),1);
		test(4,instance.exports.growSize(65536),1);
		test(5,instance.exports.getPage(),1);
		test(6,instance.exports.growSize(65537),1);
		test(7,instance.exports.getPage(),2);
		test(8,instance.exports.growSize(365*65536),1);
		test(9,instance.exports.getPage(),365);
		test(10,instance.exports.growSize(362*65536),1);
		test(11,instance.exports.getPage(),365);
		test(12,instance.exports.growSize(100*1024*1024),1);
		test(13,instance.exports.getPage(),100*1024*1024/65536);
		test(14,instance.exports.growSize(100*1024*1024+1),0); // 超出预先设定的 100M 上限
		test(15,instance.exports.getPage(),100*1024*1024/65536);
	}

	// fs.writeFileSync("main.wat",module.toText({foldExprs: true, inlineExport: true}));
	// module.destroy();
}) () ;
