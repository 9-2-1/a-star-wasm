let iconv = require("iconv-lite");
let fs = require("fs");
(async () => {
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
	let instance = await WebAssembly.instantiate(wmodule);

	// test everything here

	// fs.writeFileSync("main.wat",module.toText({foldExprs: true, inlineExport: true}));
	// module.destroy();
}) () ;
