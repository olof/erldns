-module(rr).
-include("include/nsrecs.hrl").
-export([pack_message/1, string_to_domain_name/1]).

%% Pack the header into its wire format
pack_header(Header) ->
  [Id, Qr, Opcode, Aa, Tc, Rd, Ra, Z, Rcode, Qdcount, Ancount, Nscount, Arcount] = [
    Header#header.id,
    Header#header.qr,
    Header#header.opcode,
    Header#header.aa,
    Header#header.tc,
    Header#header.rd,
    Header#header.ra,
    Header#header.z,
    Header#header.rcode,
    Header#header.qdcount,
    Header#header.ancount,
    Header#header.nscount,
    Header#header.arcount
  ],
  <<Id:16, Qr:1, Opcode:4, Aa:1, Tc:1, Rd:1, Ra:1, Z:3, Rcode:4, Qdcount:16, Ancount:16, Nscount:16, Arcount:16>>.

pack_question(Question) ->
  list_to_binary(lists:map(
    fun(Q) ->
        [Qname, Qtype, Qclass] = [string_to_domain_name(Q#question.qname), Q#question.qtype, Q#question.qclass],
        <<Qname/binary, Qtype:16, Qclass:16>>
    end,
  Question)).

%% Pack a message into its binary wire format.
pack_message(Message) ->
  Header = pack_header(Message#message.header),
  Question = pack_question(Message#message.question),
  Answer = pack_records(Message#message.answer),
  Authority = pack_records(Message#message.authority),
  Additional = pack_records(Message#message.additional),
  <<Header/binary, Question/binary, Answer/binary, Authority/binary, Additional/binary>>.

%% Pack a set of records into their wire format.
pack_records(Records) ->
  list_to_binary(lists:map(
    fun(R) ->
        Type = R#rr.type,
        {Rdata, RDLength} = rdata_to_binary(Type, R#rr.rdata),
        [Name, Class, TTL, RData] = [
          string_to_domain_name(R#rr.rname),
          R#rr.class,
          R#rr.ttl,
          Rdata
        ],
        <<Name/binary, Type:16, Class:16, TTL:32, RDLength:16, RData/binary>>
    end,
    Records)).

rdata_to_binary(Type, Rdata) ->
  case records:type_to_atom(Type) of
    a ->
      {ok, IPv4Tuple} = inet_parse:address(Rdata),
      IPv4Address = ip_to_binary(IPv4Tuple),
      {IPv4Address, byte_size(IPv4Address)};
    cname ->
      Value = string_to_domain_name(Rdata),
      {Value, byte_size(Value)};
    _ ->
      Value = list_to_binary(Rdata),
      {Value, byte_size(Value)}
  end.

ip_to_binary({A,B,C,D}) -> <<A,B,C,D>>.

string_to_domain_name(String) ->
  NullLength = 0,
  list_to_binary(
    [lists:map(
        fun(Label) ->
            LabelLen = string:len(Label),
            BinLabel = list_to_binary(Label),
            <<LabelLen:8, BinLabel/binary>>
        end,
        string:tokens(String, ".")
      )|<<NullLength:8>>]
  ).
