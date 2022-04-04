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
	let memory;
	let wimport = {
		debug: {
			log: function(x){
				console.log(x);
			},
			tell: function(){
				for(let i=0;i<10;i++){
					let str="";
					for(let j=i*4;j<(i+1)*4;j++){
						let out="";
						let puz = memory[j];
						for(let k=0;k<8;k++){
							out="0123456789abcdef"[puz&0xF]+out;
							puz>>=4;
						}
						str+="0x"+out+" ";
					}
					console.log(str);
				}
			}
		}
	};

	// 测试 内存拓展
	if(false){
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
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

	// 小根堆测试
	if(false){
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
		test("小根堆 1",instance.exports.PQadd(0,0,1,2,3),undefined);
		test(2,memory[0],1);
		test(3,memory[1],2);
		test(4,memory[2],3);
		instance.exports.PQadd(16,0,1,1,1);
		instance.exports.PQadd(16,1,2,2,2);
		instance.exports.PQadd(16,2,3,3,3);
		// wimport.debug.tell();
		let pos;
		pos = instance.exports.PQpick(16,3);
		test(5,memory[pos/4 + 0],1);
		test(6,memory[pos/4 + 1],1);
		test(7,memory[pos/4 + 2],1);
		// wimport.debug.tell();
		pos = instance.exports.PQpick(16,2);
		test(8,memory[pos/4 + 0],2);
		test(9,memory[pos/4 + 1],2);
		test(10,memory[pos/4 + 2],2);
		// wimport.debug.tell();
		pos = instance.exports.PQpick(16,1);
		test(11,memory[pos/4 + 0],3);
		test(12,memory[pos/4 + 1],3);
		test(13,memory[pos/4 + 2],3);

		// 生成随机样例
		for(let x=1;x<=50;x++){
			let sample=[];
			let out=[];
			let ans=[];
			let count = Math.floor((Math.random()+1)*x);
			for(let a=0;a<count;a++){
				sample.push([
					Math.floor(Math.random()*0x7fffffff),
					Math.floor(Math.random()*0x7fffffff),
					Math.floor(Math.random()*0x7fffffff)
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
			// console.log(String(sample));
			// 在第三个数有重复的时候有可能结果正确但是样例不会过，我目前还没做特判
			test("样例"+x,String(out),String(ans));
		}
	}

	// 寻路测试
	if(true){
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
		test("1",instance.exports.growSize(4),1);
		//console.log(require("util").inspect(instance.exports,true,null,true));
		instance.exports.mapX.value = 2;
		instance.exports.mapY.value = 2;
		memory[0] = 0;
		memory[1] = 0;
		memory[2] = 0;
		memory[3] = 0;
		test(2,instance.exports.a_star(0,0,1,1),2);
	}

	// fs.writeFileSync("main.wat",module.toText({foldExprs: true, inlineExport: true}));
	// module.destroy();
}) () ;
