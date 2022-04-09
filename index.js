let map_draw = document.getElementById("map-draw");
let map_mapX = document.getElementById("map-mapX");
let map_mapY = document.getElementById("map-mapY");
let map_cross = document.getElementById("map-cross");

let instance, memory, mapStart, path;
async function loadwasm() {
	let bin = await (await fetch("main.wasm")).arrayBuffer();
	let wmodule = await WebAssembly.compile(bin);
	let wimport = {
		debug: {
			log: function(x) {
				console.log(x);
			},
			tell: function(x, y) {
				console.log(x + " ->");
				for (let i = 0; i < y / 4; i++) {
					let str = "";
					for (let j = i * 4; j < (i + 1) * 4; j++) {
						let out = "";
						let puz = memory[mapStart + i / 4 + j];
						for (let k = 0; k < 8; k++) {
							out = "0123456789abcdef" [puz & 0xF] + out;
							puz >>= 4;
						}
						str += "0x" + out + " ";
					}
					console.log(str);
				}
			},
			inspect: function(x1, y1, x2, y2, path) {
				let mapX = instance.exports.mapX.value;
				let mapY = instance.exports.mapY.value;
				let mapStart = instance.exports.mapStart.value / 4;
				let diStart = instance.exports.diStart.value / 4;
				let fnStart = instance.exports.fnStart.value / 4;
				let gnStart = instance.exports.gnStart.value / 4;
				//console.log("map");
				//console.log(mapStart,diStart,fnStart,gnStart);
				//console.log(memory);
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += memory[mapStart + y * mapX + x] === 1 ? "##" : "::";
					}
					console.log(str);
				}
				console.log("di");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (memory[fnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							"↖↑↗←⊙→↙↓↘" [memory[diStart + y * mapX + x]] + " "
						);
					}
					console.log(str);
				}
				console.log("fn");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (
							memory[fnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							("  " + memory[fnStart + y * mapX + x]).slice(-2));
					}
					console.log(str);
				}
				console.log("gn");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (
							memory[gnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							("  " + memory[gnStart + y * mapX + x]).slice(-2));
					}
					console.log(str);
				}
				if (arguments.length !== 0) {
					console.log("path");
					let disp = [];
					for (let y = 0; y < mapY; y++) {
						disp.push([]);
						for (let x = 0; x < mapX; x++) {
							disp[y].push(
								memory[mapStart + y * mapX + x] === 0 ? "::" : "##"
							);
						}
					}
					//console.log(mapX,mapY,path);
					for (let i = 0; i < path.length; i += 2) {
						disp[path[i]][path[i + 1]] = "[]";
					}
					disp[y1][x1] = "<>";
					disp[y2][x2] = "()";
					for (let y = 0; y < mapY; y++) {
						console.log(disp[y].join(""));
					}
				}
			}
		}
	};
	instance = await WebAssembly.instantiate(wmodule, wimport);
}

let mapX = 0,
	mapY = 0,
	stX, stY, edX, edY;

function mapScale() {
	let mX = Math.min(Math.floor(Math.max(Number(map_mapX.value), 1)), 1000);
	let mY = Math.min(Math.floor(Math.max(Number(map_mapY.value), 1)), 1000);
	if (instance.exports.init(mX, mY) === 0) {
		return false;
	} else {
		mapStart = instance.exports.mapStart.value / 4;
		memory = new Uint32Array(instance.exports.memory.buffer);
		for (i = 0; i < mX * mY; i++) {
			memory[mapStart + i] = 0;
		}
		mapX = mX;
		mapY = mY;
		stX = 0;
		stY = 0;
		edX = mX - 1;
		edY = mY - 1;
		path = mapCalc();
		mapDraw();
		return true;
	}
}

loadwasm().then(function() {
	mapScale();
	map_mapX.addEventListener("change", mapScale);
	map_mapY.addEventListener("change", mapScale);
	map_cross.addEventListener("change", function(event) {
		path = mapCalc();
		mapDraw();
	});
	window.addEventListener("resize", mapDraw);
}).catch((e) => {
	alert(e.message);
});

function mapDraw() {
	let scale = Math.min(
		(document.body.clientWidth - 40) / mapX,
		(document.body.clientHeight - 40) / mapY
	);
	map_draw.style.width = scale * mapX + "px";
	map_draw.style.height = scale * mapY + "px";
	map_draw.style.border = "1px white solid";
	map_draw.width = mapX * 30;
	map_draw.height = mapY * 30;
	let ct = map_draw.getContext("2d");
	ct.clearRect(0, 0, mapX * 30, mapY * 30);
	ct.fillStyle = "#000000";
	for (let y = 0; y < mapY; y++) {
		for (let x = 0; x < mapX; x++) {
			if (memory[mapStart + y * mapX + x] === 1) {
				ct.fillRect(30 * x, 30 * y, 30, 30);
			}
		}
	}
	ct.fillStyle = "#d0d000";
	for (let i = 0; i < path.length; i += 2) {
		ct.fillRect(30 * path[i + 1], 30 * path[i], 30, 30);
	}
	ct.fillStyle = "#ff0000";
	ct.fillRect(30 * stX, 30 * stY, 30, 30);
	ct.fillStyle = "#00d000";
	ct.fillRect(30 * edX, 30 * edY, 30, 30);
}

map_draw.addEventListener("touchstart", mapChangeStart);
map_draw.addEventListener("touchmove", mapChangeStep);
map_draw.addEventListener("mousedown", mapChangeStart);
map_draw.addEventListener("mousemove", mapChangeStep);
window.addEventListener("mouseleave", mapChangeStop);
map_draw.addEventListener("mouseup", mapChangeStop);

let changeMode = -1;

function mapChangeStart(event) {
	return mapChangeStep(event, true);
}

function mapChangeStep(event, isStart) {
	let rect = event.target.getBoundingClientRect();
	let xd = ((event.targetTouches[0].clientX - rect.left) / rect.width);
	let yd = ((event.targetTouches[0].clientY - rect.top) / rect.height);
	if (0 <= xd && xd < 1 && 0 <= yd && yd < 1) {
		let xg = Math.floor(xd * mapX);
		let yg = Math.floor(yd * mapY);
		if (isStart) {
			if (xg === edX && yg === edY) {
				changeMode = 3;
			} else if (xg === stX && yg === stY) {
				changeMode = 2;
			} else {
				changeMode = memory[mapStart + yg * mapX + xg] ^= 1;
			}
		} else {
			switch (changeMode) {
				case -1:
					return;
				case 2:
					if (memory[mapStart + yg * mapX + xg] === 0 && !(xg === edX && yg === edY)) {
						stX = xg;
						stY = yg;
					}
					break;
				case 3:
					if (memory[mapStart + yg * mapX + xg] === 0 && !(xg === stX && yg === stY)) {
						edX = xg;
						edY = yg;
					}
					break;
				default:
					if (!(xg === edX && yg === edY) && !(xg === stX && yg === stY)) {
						memory[mapStart + yg * mapX + xg] = changeMode;
					}
			}
		}
		path = mapCalc();
		mapDraw();
		event.preventDefault();
	}
}

function mapChangeStop(event) {
	changeMode = -1;
}

function mapCalc() {
	let mode = map_cross.checked ? 2 : 1;
	let out = instance.exports.a_star(stX, stY, edX, edY, mode);
	if (out === -1) {
		return [];
	} else {
		let path = [];
		let st = instance.exports.pathStart.value / 4;
		for (let i = 0; i < out; i++) {
			let dt = memory[st + i];
			path.push(dt >> 16);
			path.push(dt & 0xffff);
		}
		return path;
	}
}
