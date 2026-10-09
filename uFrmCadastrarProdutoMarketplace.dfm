object FrmCadastrarProdutoMarketplace: TFrmCadastrarProdutoMarketplace
  Left = 0
  Top = 0
  Caption = 'Incluir Produto'
  ClientHeight = 620
  ClientWidth = 560
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object lblNome: TLabel
    Left = 16
    Top = 60
    Width = 96
    Height = 15
    Caption = 'Nome do Produto'
  end
  object lblDescricao: TLabel
    Left = 16
    Top = 108
    Width = 51
    Height = 15
    Caption = 'Descri'#231#227'o'
  end
  object lblImagem: TLabel
    Left = 16
    Top = 216
    Width = 44
    Height = 15
    Caption = 'Imagem'
  end
  object lblPreco: TLabel
    Left = 16
    Top = 268
    Width = 30
    Height = 15
    Caption = 'Pre'#231'o'
  end
  object lblEstoque: TLabel
    Left = 152
    Top = 268
    Width = 42
    Height = 15
    Caption = 'Estoque'
  end
  object lblPeso: TLabel
    Left = 288
    Top = 268
    Width = 49
    Height = 15
    Caption = 'Peso (kg)'
  end
  object lblCategoriaID: TLabel
    Left = 16
    Top = 322
    Width = 203
    Height = 15
    Caption = 'Categoria ID (0 = detectar autom'#225'tico)'
  end
  object lblBrandID: TLabel
    Left = 192
    Top = 322
    Width = 134
    Height = 15
    Caption = 'Brand ID (0 = sem marca)'
  end
  object lblBrandName: TLabel
    Left = 328
    Top = 322
    Width = 85
    Height = 15
    Caption = 'Nome da Marca'
  end
  object lblSku: TLabel
    Left = 16
    Top = 322
    Width = 21
    Height = 15
    Caption = 'SKU'
  end
  object lblAsin: TLabel
    Left = 192
    Top = 322
    Width = 26
    Height = 15
    Caption = 'ASIN'
  end
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 560
    Height = 50
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 15
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 115
      Height = 21
      Caption = 'Incluir Produto'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object edtNome: TEdit
    Left = 16
    Top = 78
    Width = 528
    Height = 23
    TabOrder = 0
  end
  object mmDescricao: TMemo
    Left = 16
    Top = 126
    Width = 528
    Height = 80
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object edtImagem: TEdit
    Left = 16
    Top = 234
    Width = 424
    Height = 23
    ReadOnly = True
    TabOrder = 2
  end
  object CmdProcurarImagem: TBitBtn
    Left = 448
    Top = 233
    Width = 96
    Height = 25
    Caption = 'Procurar...'
    TabOrder = 3
    OnClick = CmdProcurarImagemClick
  end
  object edtPreco: TEdit
    Left = 16
    Top = 286
    Width = 120
    Height = 23
    TabOrder = 4
    Text = '0,00'
  end
  object edtEstoque: TEdit
    Left = 152
    Top = 286
    Width = 120
    Height = 23
    TabOrder = 5
    Text = '0'
  end
  object edtPeso: TEdit
    Left = 288
    Top = 286
    Width = 120
    Height = 23
    TabOrder = 6
  end
  object edtCategoriaID: TEdit
    Left = 16
    Top = 340
    Width = 160
    Height = 23
    TabOrder = 7
  end
  object edtBrandID: TEdit
    Left = 192
    Top = 340
    Width = 120
    Height = 23
    TabOrder = 8
  end
  object edtBrandName: TEdit
    Left = 328
    Top = 340
    Width = 216
    Height = 23
    TabOrder = 9
  end
  object edtSku: TEdit
    Left = 16
    Top = 340
    Width = 160
    Height = 23
    TabOrder = 11
  end
  object edtAsin: TEdit
    Left = 192
    Top = 340
    Width = 160
    Height = 23
    TabOrder = 12
  end
  object CmdCadastrar: TBitBtn
    Left = 16
    Top = 380
    Width = 160
    Height = 34
    Caption = 'Cadastrar'
    TabOrder = 10
    OnClick = CmdCadastrarClick
  end
  object CmdFechar: TBitBtn
    Left = 184
    Top = 380
    Width = 100
    Height = 34
    Caption = 'Fechar'
    TabOrder = 13
    OnClick = CmdFecharClick
  end
  object MemoLog: TMemo
    Left = 16
    Top = 428
    Width = 528
    Height = 176
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 14
  end
  object OpenDialogImagem: TOpenDialog
    Filter = 'Imagens (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png'
    Title = 'Selecionar imagem do produto'
    Left = 480
    Top = 60
  end
end
