import { createClient } from "npm:@supabase/supabase-js@2";
const headers={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers});
 if(req.method!=="POST")return reply(405,{error:"Method not allowed"});
 try{
  const authorization=req.headers.get("Authorization");
  if(!authorization?.startsWith("Bearer "))return reply(401,{error:"Sign in required"});
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service)return reply(500,{error:"Server configuration missing"});
  const client=createClient(url,anon),admin=createClient(url,service);
  const {data:{user},error:authError}=await client.auth.getUser(authorization.slice(7));
  if(authError||!user)return reply(401,{error:"Invalid session"});
  const body=await req.json().catch(()=>null),bookingId=body?.booking_id,amount=body?.amount_cents;
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if(typeof bookingId!=="string"||!uuid.test(bookingId)||!Number.isSafeInteger(amount)||amount<100||amount>100000000)return reply(400,{error:"Valid booking and price between $1 and $1,000,000 required"});
  const {data:booking,error:bookingError}=await admin.from("bookings").select("id,provider_id,customer_id,status").eq("id",bookingId).single();
  if(bookingError||!booking)return reply(404,{error:"Booking not found"});
  if(booking.provider_id!==user.id)return reply(403,{error:"Only the assigned worker may quote this booking"});
  if(booking.status!=="accepted")return reply(409,{error:"Booking must be accepted before quoting"});
  const {data:existing,error:existingError}=await admin.from("booking_quotes").select("id,status").eq("booking_id",bookingId).limit(1);
  if(existingError)return reply(500,{error:"Could not check existing quotes"});
  if(existing?.length)return reply(409,{error:"A quote already exists for this booking"});
  const {data:quote,error}=await admin.from("booking_quotes").insert({booking_id:bookingId,provider_id:user.id,amount_cents:amount,currency:"usd",status:"proposed"}).select("id").single();
  if(error){console.error("Quote insert failed:",error.message);return reply(500,{error:"Could not save quote"});}
  return reply(200,{success:true,quote_id:quote.id,status:"proposed"});
 }catch{return reply(500,{error:"Unable to submit quote"});}
});
