object FrmCadastrarProdutoAmazonNovo: TFrmCadastrarProdutoAmazonNovo
  Left = 0
  Top = 0
  Caption = 'Incluir Produto Novo - Amazon'
  ClientHeight = 898
  ClientWidth = 620
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 620
    Height = 50
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 300
      Height = 21
      Caption = 'Incluir Produto Novo - Amazon'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object lblKeywords: TLabel
    Left = 16
    Top = 60
    Width = 460
    Height = 15
    Caption = 
      'Busque a categoria (productType) por palavra-chave (ex: "clip' +
      'e de papel", "mochila")'
  end
  object edtKeywords: TEdit
    Left = 16
    Top = 80
    Width = 420
    Height = 23
    TabOrder = 1
  end
  object CmdBuscarProductType: TBitBtn
    Left = 444
    Top = 79
    Width = 160
    Height = 25
    Caption = 'Buscar Categoria'
    TabOrder = 2
    OnClick = CmdBuscarProductTypeClick
  end
  object lstProductTypes: TListBox
    Left = 16
    Top = 112
    Width = 588
    Height = 220
    ItemHeight = 15
    TabOrder = 3
  end
  object CmdProximoPasso1: TBitBtn
    Left = 16
    Top = 340
    Width = 200
    Height = 34
    Caption = 'Continuar >>'
    TabOrder = 4
    OnClick = CmdProximoPasso1Click
  end
  object lblOuBuscarCatalogo: TLabel
    Left = 16
    Top = 384
    Width = 588
    Height = 15
    Caption = 
      'Ou busque se o produto ja existe no catalogo da Amazon (evita ' +
      'cadastro do zero):'
  end
  object edtBuscaCatalogo: TEdit
    Left = 16
    Top = 404
    Width = 420
    Height = 23
    TabOrder = 5
  end
  object CmdBuscarCatalogo: TBitBtn
    Left = 444
    Top = 403
    Width = 160
    Height = 25
    Caption = 'Buscar no Catalogo'
    TabOrder = 6
    OnClick = CmdBuscarCatalogoClick
  end
  object lstResultadosCatalogo: TListBox
    Left = 16
    Top = 434
    Width = 588
    Height = 130
    ItemHeight = 15
    TabOrder = 7
  end
  object CmdUsarASINExistente: TBitBtn
    Left = 16
    Top = 570
    Width = 320
    Height = 28
    Caption = 'Usar ASIN selecionado (produto ja existe)'
    TabOrder = 8
    OnClick = CmdUsarASINExistenteClick
  end
  object lblProductTypeSelecionado: TLabel
    Left = 16
    Top = 60
    Width = 160
    Height = 15
    Caption = 'Categoria selecionada:'
  end
  object lblSku: TLabel
    Left = 16
    Top = 84
    Width = 25
    Height = 15
    Caption = 'SKU'
  end
  object edtSku: TEdit
    Left = 16
    Top = 102
    Width = 160
    Height = 23
    TabOrder = 9
  end
  object lblNome: TLabel
    Left = 192
    Top = 84
    Width = 100
    Height = 15
    Caption = 'Nome do Produto'
  end
  object edtNome: TEdit
    Left = 192
    Top = 102
    Width = 412
    Height = 23
    TabOrder = 10
  end
  object lblBulletPoints: TLabel
    Left = 16
    Top = 132
    Width = 300
    Height = 15
    Caption = 'Bullet points (um por linha, opcional)'
  end
  object mmBulletPoints: TMemo
    Left = 16
    Top = 150
    Width = 588
    Height = 70
    ScrollBars = ssVertical
    TabOrder = 11
  end
  object lblMarca: TLabel
    Left = 16
    Top = 228
    Width = 90
    Height = 15
    Caption = 'Marca (brand)'
  end
  object edtMarca: TEdit
    Left = 16
    Top = 246
    Width = 180
    Height = 23
    TabOrder = 12
  end
  object lblPaisOrigem: TLabel
    Left = 210
    Top = 228
    Width = 92
    Height = 15
    Caption = 'Pa'#237's de Origem'
  end
  object edtPaisOrigem: TEdit
    Left = 210
    Top = 246
    Width = 80
    Height = 23
    TabOrder = 13
    Text = 'BR'
  end
  object lblDescricao: TLabel
    Left = 16
    Top = 278
    Width = 400
    Height = 15
    Caption = 'Descri'#231#227'o do produto'
  end
  object mmDescricao: TMemo
    Left = 16
    Top = 296
    Width = 588
    Height = 50
    ScrollBars = ssVertical
    TabOrder = 14
  end
  object lblCodigoBarras: TLabel
    Left = 16
    Top = 354
    Width = 260
    Height = 15
    Caption = 'C'#243'digo de Barras (EAN/UPC/GTIN, se tiver)'
  end
  object cbTipoCodigoBarras: TComboBox
    Left = 16
    Top = 372
    Width = 100
    Height = 23
    Style = csDropDownList
    ItemIndex = 0
    TabOrder = 15
    Items.Strings = (
      'EAN'
      'UPC'
      'GTIN')
    Text = 'EAN'
  end
  object edtCodigoBarras: TEdit
    Left = 124
    Top = 372
    Width = 200
    Height = 23
    TabOrder = 16
  end
  object lblPreco: TLabel
    Left = 16
    Top = 402
    Width = 32
    Height = 15
    Caption = 'Pre'#231'o'
  end
  object edtPreco: TEdit
    Left = 16
    Top = 420
    Width = 120
    Height = 23
    TabOrder = 17
    Text = '0,00'
  end
  object lblEstoque: TLabel
    Left = 152
    Top = 402
    Width = 45
    Height = 15
    Caption = 'Estoque'
  end
  object edtEstoque: TEdit
    Left = 152
    Top = 420
    Width = 120
    Height = 23
    TabOrder = 18
    Text = '0'
  end
  object CmdMontarJSON: TBitBtn
    Left = 300
    Top = 419
    Width = 150
    Height = 25
    Caption = 'Montar/Atualizar JSON'
    TabOrder = 19
    OnClick = CmdMontarJSONClick
  end
  object CmdVerSchema: TBitBtn
    Left = 460
    Top = 419
    Width = 144
    Height = 25
    Caption = 'Ver Schema Completo'
    TabOrder = 20
    OnClick = CmdVerSchemaClick
  end
  object lblAtributosJSON: TLabel
    Left = 16
    Top = 454
    Width = 400
    Height = 15
    Caption = 'Atributos (JSON) - revise antes de cadastrar'
  end
  object mmAtributosJSON: TMemo
    Left = 16
    Top = 472
    Width = 588
    Height = 170
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssBoth
    TabOrder = 21
    WordWrap = False
  end
  object CmdVoltar: TBitBtn
    Left = 16
    Top = 652
    Width = 100
    Height = 34
    Caption = '<< Voltar'
    TabOrder = 22
    OnClick = CmdVoltarClick
  end
  object CmdCadastrar: TBitBtn
    Left = 124
    Top = 652
    Width = 180
    Height = 34
    Caption = 'Cadastrar Produto'
    TabOrder = 23
    OnClick = CmdCadastrarClick
  end
  object CmdFechar: TBitBtn
    Left = 480
    Top = 652
    Width = 124
    Height = 34
    Caption = 'Fechar'
    TabOrder = 24
    OnClick = CmdFecharClick
  end
  object MemoLog: TMemo
    Left = 16
    Top = 696
    Width = 588
    Height = 182
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 25
  end
end
