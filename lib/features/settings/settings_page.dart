import 'package:flutter/material.dart';
import '../../app/marginal_theme.dart';
import '../../app/provider_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  final _store=ProviderStore();
  @override void initState(){super.initState();_store.load();}
  @override void dispose(){_store.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('设置')),body:AnimatedBuilder(animation:_store,builder:(_,__)=>ListView(padding:const EdgeInsets.only(top:12,bottom:48),children:[
    _section('AI 供应商', '为修复、实体提取和插图配置用户自己的模型服务'),
    ..._store.providers.map((p)=>_ProviderCard(store:_store,entry:p)),
    Padding(padding:const EdgeInsets.all(16),child:OutlinedButton.icon(onPressed:()=>_edit(null),icon:const Icon(Icons.add),label:const Text('添加 OpenAI-compatible 供应商'))),
    _section('阅读', '阅读器的字号、主题、自动阅读速度可在阅读页随时调整'),
    const ListTile(leading:Icon(Icons.security),title:Text('密钥安全'),subtitle:Text('移动端保存在系统安全存储；Web 端由浏览器安全模型保护。')),
  ])));
  Widget _section(String title,String text)=>Padding(padding:const EdgeInsets.fromLTRB(20,18,20,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily:'Songti SC')),const SizedBox(height:4),Text(text,style:Theme.of(context).textTheme.bodySmall)]));
  Future<void> _edit(ProviderEntry? existing) async { final name=TextEditingController(text:existing?.name??'');final url=TextEditingController(text:existing?.baseUrl??'https://api.example.com/v1');final key=TextEditingController(text:existing?.apiKey??'');final model=TextEditingController(text:existing?.model??''); final result=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:Text(existing==null?'添加供应商':'编辑供应商'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'名称')),TextField(controller:url,decoration:const InputDecoration(labelText:'Base URL')),TextField(controller:key,obscureText:true,decoration:const InputDecoration(labelText:'API Key')),TextField(controller:model,decoration:const InputDecoration(labelText:'模型'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('保存'))])); if(result==true&&name.text.trim().isNotEmpty){final id=existing?.id??'provider-${DateTime.now().microsecondsSinceEpoch}';await _store.upsert(ProviderEntry(id:id,name:name.text.trim(),baseUrl:url.text.trim(),apiKey:key.text,model:model.text.trim()));}}
}
class _ProviderCard extends StatelessWidget{const _ProviderCard({required this.store,required this.entry});final ProviderStore store;final ProviderEntry entry;@override Widget build(BuildContext context)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:entry.id=='demo'?MarginalColors.accentSoft:Theme.of(context).colorScheme.primaryContainer,child:Icon(entry.id=='demo'?Icons.auto_awesome:Icons.cloud)),title:Text(entry.name),subtitle:Text('${entry.model}\n${entry.baseUrl}',maxLines:2,overflow:TextOverflow.ellipsis),isThreeLine:true,trailing:Wrap(children:[IconButton(tooltip:'连通性诊断',onPressed:()async{final result=await store.diagnose(entry);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(result=='direct'?'供应商可直连':'需要代理或检查配置')));},icon:Icon(entry.diagnostic=='direct'?Icons.check_circle:Icons.network_check,color:entry.diagnostic=='direct'?MarginalColors.ok:null)),if(entry.id!='demo')PopupMenuButton<String>(onSelected:(v){if(v=='edit'){}if(v=='delete')store.remove(entry.id);},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('编辑')),PopupMenuItem(value:'delete',child:Text('删除'))])])));}

class EntitiesPage extends StatelessWidget { const EntitiesPage({super.key}); @override Widget build(BuildContext context)=>const Scaffold(body:Center(child:Text('请从书稿阅读页进入实体卡'))); }
class IllustrationsPage extends StatelessWidget { const IllustrationsPage({super.key}); @override Widget build(BuildContext context)=>const Scaffold(body:Center(child:Text('请从书稿阅读页进入插图'))); }
