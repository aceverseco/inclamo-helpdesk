import {createServer} from 'node:http';
const events=[];
createServer(async(req,res)=>{
 res.setHeader('Content-Type','application/json');
 if(req.url==='/requests') return res.end(JSON.stringify(events));
 let body='';for await(const part of req)body+=part;
 try{const data=JSON.parse(body);events.push({event:data.event,id:data.id,content:data.content,conversation_id:data.conversation?.id});res.end('{}')}
 catch{res.statusCode=400;res.end('{}')}
}).listen(8080,'0.0.0.0');
