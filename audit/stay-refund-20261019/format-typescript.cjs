const fs = require('fs');
const ts = require('../../backend/node_modules/typescript');
for (const path of ['backend/src/services/billing.ts','backend/src/routes/settlement.ts','backend/tests/settlement.integration.test.ts']) {
 const original=fs.readFileSync(path,'utf8');
 const parsed=ts.createSourceFile(path,original,ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);
 fs.writeFileSync(path,ts.createPrinter({newLine:ts.NewLineKind.LineFeed}).printFile(parsed),'utf8');
}
