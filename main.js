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
	let impor = {
		debug: {
			debug: function(x){
				console.log(x);
			}
		}
	};

	// 测试 内存拓展
	if(false){
		instance = await WebAssembly.instantiate(wmodule, impor);
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

	//
	if(true){
		instance = await WebAssembly.instantiate(wmodule, impor);
		let memory = new Uint32Array(instance.exports.memory.buffer);
		test("1",instance.exports.PQadd(0,0,1,2,3),undefined);
		test(2,memory[0],1);
		test(3,memory[1],2);
		test(4,memory[2],3);

		instance.exports.PQadd(16,0,1,1,1);
		instance.exports.PQadd(16,1,2,2,2);
		instance.exports.PQadd(16,2,3,3,3);
		let pos;
		pos = instance.exports.PQpick(16,3);
		test(5,memory[pos/4 + 0],1);
		test(6,memory[pos/4 + 1],1);
		test(7,memory[pos/4 + 2],1);
		pos = instance.exports.PQpick(16,2);
		test(8,memory[pos/4 + 0],2);
		test(9,memory[pos/4 + 1],2);
		test(10,memory[pos/4 + 2],2);
		pos = instance.exports.PQpick(16,1);
		test(8,memory[pos/4 + 0],3);
		test(9,memory[pos/4 + 1],3);
		test(10,memory[pos/4 + 2],3);

		for(let x=1;x<=10;x++){
			let sample=[];
			let out=[];
			let ans=[];
			let count = (Math.floor((Math.random()+1)*x),3);
			for(let a=0;a<count;a++){
				sample.push([
					Math.floor(Math.random()*100),
					Math.floor(Math.random()*100),
					Math.floor(Math.random()*100)
				]);
			}
			for(let a=0;a<count;a++){
				instance.exports.PQadd(0,a,
					sample[a][0],
					sample[a][1],
					sample[a][2]
				);
			}
			for(let a=0;a<count;a++){
				let pos = instance.exports.PQpick(0,count-a);
				out.push([
					memory[pos/4 + 0],
					memory[pos/4 + 1],
					memory[pos/4 + 2]
				]);
			}
			ans=sample.sort((a,b)=>a[2]-b[2]);
			console.log(String(sample));
			test("cp"+x,String(out),String(ans));
		}
	}
	// fs.writeFileSync("main.wat",module.toText({foldExprs: true, inlineExport: true}));
	// module.destroy();
}) () ;
