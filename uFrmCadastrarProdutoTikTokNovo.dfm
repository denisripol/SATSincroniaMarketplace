object FrmCadastrarProdutoTikTokNovo: TFrmCadastrarProdutoTikTokNovo
  Left = 0
  Top = 0
  Caption = 'Incluir Produto Novo - TikTok Shop'
  ClientHeight = 876
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
      Width = 320
      Height = 21
      Caption = 'Incluir Produto Novo - TikTok Shop'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object lblBuscaCategoria: TLabel
    Left = 16
    Top = 62
    Width = 440
    Height = 15
    Caption = 'Titulo do produto (o TikTok sugere a categoria):'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object edtBuscaCategoria: TEdit
    Left = 16
    Top = 82
    Width = 440
    Height = 23
    TabOrder = 1
  end
  object CmdPreverCategoria: TBitBtn
    Left = 464
    Top = 81
    Width = 140
    Height = 27
    Caption = 'Sugerir Categoria'
    TabOrder = 2
    OnClick = CmdPreverCategoriaClick
  end
  object lstCategorias: TListBox
    Left = 16
    Top = 115
    Width = 588
    Height = 160
    ItemHeight = 15
    TabOrder = 3
  end
  object CmdProximoPasso1: TBitBtn
    Left = 16
    Top = 283
    Width = 140
    Height = 27
    Caption = 'Continuar >>'
    TabOrder = 4
    OnClick = CmdProximoPasso1Click
  end
  object lblCategoriaSelecionada: TLabel
    Left = 16
    Top = 62
    Width = 588
    Height = 15
    Caption = 'Categoria:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblSku: TLabel
    Left = 16
    Top = 86
    Width = 120
    Height = 15
    Caption = 'SKU (seu codigo):'
  end
  object edtSku: TEdit
    Left = 16
    Top = 104
    Width = 270
    Height = 23
    TabOrder = 5
  end
  object lblNome: TLabel
    Left = 300
    Top = 86
    Width = 120
    Height = 15
    Caption = 'Titulo do produto:'
  end
  object edtNome: TEdit
    Left = 300
    Top = 104
    Width = 304
    Height = 23
    TabOrder = 6
  end
  object lblMarca: TLabel
    Left = 16
    Top = 134
    Width = 300
    Height = 15
    Caption = 'Marca (busque e escolha - o TikTok exige da lista dele):'
  end
  object edtBuscaMarca: TEdit
    Left = 16
    Top = 152
    Width = 200
    Height = 23
    TabOrder = 7
  end
  object CmdBuscarMarca: TBitBtn
    Left = 224
    Top = 151
    Width = 100
    Height = 26
    Caption = 'Buscar'
    TabOrder = 8
    OnClick = CmdBuscarMarcaClick
  end
  object cbMarca: TComboBox
    Left = 332
    Top = 152
    Width = 272
    Height = 23
    Style = csDropDownList
    TabOrder = 9
  end
  object lblPreco: TLabel
    Left = 16
    Top = 182
    Width = 120
    Height = 15
    Caption = 'Preco (R$):'
  end
  object edtPreco: TEdit
    Left = 16
    Top = 200
    Width = 136
    Height = 23
    TabOrder = 10
  end
  object lblEstoque: TLabel
    Left = 160
    Top = 182
    Width = 120
    Height = 15
    Caption = 'Estoque:'
  end
  object edtEstoque: TEdit
    Left = 160
    Top = 200
    Width = 136
    Height = 23
    TabOrder = 11
  end
  object lblPeso: TLabel
    Left = 304
    Top = 182
    Width = 110
    Height = 15
    Caption = 'Peso (kg) - obrig.:'
  end
  object edtPeso: TEdit
    Left = 304
    Top = 200
    Width = 136
    Height = 23
    TabOrder = 12
  end
  object lblDimensoes: TLabel
    Left = 448
    Top = 182
    Width = 156
    Height = 15
    Caption = 'Dimensoes C/L/A (cm):'
  end
  object edtComprimento: TEdit
    Left = 448
    Top = 200
    Width = 48
    Height = 23
    TabOrder = 22
  end
  object edtLargura: TEdit
    Left = 500
    Top = 200
    Width = 48
    Height = 23
    TabOrder = 23
  end
  object edtAltura: TEdit
    Left = 552
    Top = 200
    Width = 52
    Height = 23
    TabOrder = 24
  end
  object lblImagens: TLabel
    Left = 16
    Top = 230
    Width = 588
    Height = 15
    Caption = 'Imagens - CAMINHO DO ARQUIVO no computador, um por linha (o TikTok nao aceita link):'
  end
  object mmImagens: TMemo
    Left = 16
    Top = 248
    Width = 588
    Height = 60
    ScrollBars = ssVertical
    TabOrder = 13
  end
  object lblDescricao: TLabel
    Left = 16
    Top = 316
    Width = 588
    Height = 15
    Caption = 'Descricao:'
  end
  object mmDescricao: TMemo
    Left = 16
    Top = 334
    Width = 588
    Height = 70
    ScrollBars = ssVertical
    TabOrder = 14
  end
  object CmdMontarJSON: TBitBtn
    Left = 16
    Top = 412
    Width = 180
    Height = 27
    Caption = 'Montar/Atualizar JSON'
    TabOrder = 15
    OnClick = CmdMontarJSONClick
  end
  object CmdVerAtributos: TBitBtn
    Left = 204
    Top = 412
    Width = 200
    Height = 27
    Caption = 'Ver Atributos da Categoria'
    TabOrder = 16
    OnClick = CmdVerAtributosClick
  end
  object lblAtributosJSON: TLabel
    Left = 16
    Top = 446
    Width = 588
    Height = 15
    Caption = 'Atributos obrigatorios (preencha os valores antes de publicar):'
  end
  object mmAtributosJSON: TMemo
    Left = 16
    Top = 464
    Width = 588
    Height = 170
    ScrollBars = ssVertical
    TabOrder = 17
  end
  object CmdVoltar: TBitBtn
    Left = 16
    Top = 642
    Width = 120
    Height = 27
    Caption = '<< Voltar'
    TabOrder = 18
    OnClick = CmdVoltarClick
  end
  object CmdCadastrar: TBitBtn
    Left = 144
    Top = 642
    Width = 180
    Height = 27
    Caption = 'Publicar Produto'
    TabOrder = 19
    OnClick = CmdCadastrarClick
  end
  object CmdFechar: TBitBtn
    Left = 484
    Top = 676
    Width = 120
    Height = 27
    Caption = 'Fechar'
    TabOrder = 20
    OnClick = CmdFecharClick
  end
  object MemoLog: TMemo
    Left = 16
    Top = 710
    Width = 588
    Height = 150
    ScrollBars = ssVertical
    TabOrder = 21
    ReadOnly = True
  end
end
