// 시뮬레이터의 특정 좌표를 누른다(expo-mcp의 XCTest 드라이버를 직접 부름 — MCP 재연결 없이 바로).
//   node tap.mjs <appDir> <udid> <appId> <x> <y>   (좌표는 pt — 캡처 px ÷ 화면 배율)
import { pathToFileURL } from "node:url";
import path from "node:path";
const [appDir, udid, appId, x, y] = process.argv.slice(2);
const mod = await import(pathToFileURL(path.join(appDir, "node_modules/expo-mcp/dist/automation/AutomationIos.js")).href);
const automation = new mod.AutomationIos({ appId, deviceId: udid });
const result = await automation.tapAsync({ x: Number(x), y: Number(y) });
console.log(result.success ? `tap ${x},${y} ok` : `tap ${x},${y} failed: ${JSON.stringify(result).slice(0, 200)}`);
